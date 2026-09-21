import { PutItemCommand, DynamoDBClient } from "@aws-sdk/client-dynamodb";
import net from "node:net";
import {
  DescribeInstancesCommand,
  EC2Client,
  Instance,
  InstanceStateName,
  StartInstancesCommand,
} from "@aws-sdk/client-ec2";
import { SendCommandCommand, SSMClient } from "@aws-sdk/client-ssm";
import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import {
  InteractionResponseType,
  InteractionType,
  verifyKey,
} from "discord-interactions";

const DISCORD_PUBLIC_KEY = process.env.DISCORD_PUBLIC_KEY;
const PROJECT_TAG = process.env.SERVER_PROJECT_TAG_VALUE ?? "minecraft-server";
const ALLOWED_GUILD_ID = process.env.ALLOWED_GUILD_ID || undefined;
const INTERACTION_TABLE = process.env.DISCORD_INTERACTION_TABLE;
const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";
const MAX_INTERACTION_AGE_SECONDS = 300;
const INTERACTION_TTL_SECONDS = 900;
const STATUS_PROBE_TIMEOUT_MS = 1500;

const ec2Client = new EC2Client({ region: AWS_REGION });
const ssmClient = new SSMClient({ region: AWS_REGION });
const dynamoClient = new DynamoDBClient({ region: AWS_REGION });

type DiscordOption = {
  name?: string;
  type?: number;
  value?: string;
  focused?: boolean;
  options?: DiscordOption[];
};

export type MinecraftServer = {
  key: string;
  name: string;
  instanceId: string;
  publicIp?: string;
  port: number;
  profile: string;
  state: InstanceStateName | "unknown";
  launchedAt?: number;
};

type MinecraftProbe = {
  playersOnline: number;
  playersMax: number;
};

const response = (content: string): APIGatewayProxyResult => ({
  statusCode: 200,
  body: JSON.stringify({
    type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
    data: { content },
  }),
});

const tagValue = (instance: Instance, key: string): string | undefined =>
  instance.Tags?.find((tag) => tag.Key === key)?.Value;

export const portFromTag = (instance: Instance): number => {
  const parsed = Number(tagValue(instance, "MinecraftPort") ?? "25565");
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 65535
    ? parsed
    : 25565;
};

const listServers = async (): Promise<MinecraftServer[]> => {
  const result = await ec2Client.send(
    new DescribeInstancesCommand({
      Filters: [
        { Name: "tag:Project", Values: [PROJECT_TAG] },
        { Name: "tag:DiscordManaged", Values: ["true"] },
        {
          Name: "instance-state-name",
          Values: ["pending", "running", "shutting-down", "stopping", "stopped"],
        },
      ],
    }),
  );

  return (
    result.Reservations?.flatMap((reservation) => reservation.Instances ?? []) ?? []
  )
    .map((instance) => ({
      key: tagValue(instance, "MinecraftServer") ?? "",
      name:
        tagValue(instance, "MinecraftName") ??
        tagValue(instance, "Name") ??
        tagValue(instance, "MinecraftServer") ??
        "Minecraft server",
      instanceId: instance.InstanceId ?? "",
      publicIp: instance.PublicIpAddress,
      port: portFromTag(instance),
      profile: tagValue(instance, "MinecraftProfile") ?? "unknown profile",
      state: (instance.State?.Name ?? "unknown") as MinecraftServer["state"],
      launchedAt: instance.LaunchTime?.getTime(),
    }))
    .filter((server) => server.key && server.instanceId)
    .sort((left, right) => left.key.localeCompare(right.key));
};

const findOption = (
  options: DiscordOption[] | undefined,
  predicate: (option: DiscordOption) => boolean,
): DiscordOption | undefined => {
  for (const option of options ?? []) {
    if (predicate(option)) return option;
    const nested = findOption(option.options, predicate);
    if (nested) return nested;
  }
  return undefined;
};

export const statusEmoji = (state: MinecraftServer["state"]): string => {
  if (state === "running") return "🟢";
  if (state === "stopped") return "🔴";
  if (["pending", "shutting-down", "stopping"].includes(state)) return "🟡";
  return "⚪";
};

export const describeServer = (server: MinecraftServer): string => {
  const address = server.publicIp ? ` — ${server.publicIp}:${server.port}` : "";
  return `${statusEmoji(server.state)} **${server.name}**${address} — ${server.state}`;
};

export const formatUptime = (launchedAt: number | undefined, now = Date.now()): string => {
  if (launchedAt === undefined || launchedAt > now) return "";
  const minutes = Math.floor((now - launchedAt) / 60000);
  const hours = Math.floor(minutes / 60);
  return hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`;
};

const encodeVarInt = (value: number): Buffer => {
  const bytes: number[] = [];
  let remaining = value >>> 0;
  do {
    let current = remaining & 0x7f;
    remaining >>>= 7;
    if (remaining !== 0) current |= 0x80;
    bytes.push(current);
  } while (remaining !== 0);
  return Buffer.from(bytes);
};

const decodeVarInt = (buffer: Buffer, offset = 0): { value: number; size: number } | undefined => {
  let value = 0;
  for (let index = 0; index < 5; index += 1) {
    const position = offset + index;
    if (position >= buffer.length) return undefined;
    const current = buffer[position];
    value |= (current & 0x7f) << (7 * index);
    if ((current & 0x80) === 0) return { value, size: index + 1 };
  }
  throw new Error("Invalid Minecraft status packet.");
};

const minecraftStatusPacket = (host: string, port: number): Buffer => {
  const hostBytes = Buffer.from(host, "utf8");
  const handshake = Buffer.concat([
    Buffer.from([0]),
    encodeVarInt(-1),
    encodeVarInt(hostBytes.length),
    hostBytes,
    Buffer.from([(port >> 8) & 0xff, port & 0xff]),
    Buffer.from([1]),
  ]);
  return Buffer.concat([
    encodeVarInt(handshake.length),
    handshake,
    Buffer.from([1, 0]),
  ]);
};

export const probeMinecraft = (host: string, port: number, timeoutMs = STATUS_PROBE_TIMEOUT_MS): Promise<MinecraftProbe> =>
  new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    let received = Buffer.alloc(0);
    let settled = false;
    const finish = (error?: Error, probe?: MinecraftProbe) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      clearTimeout(timeout);
      if (error) reject(error);
      else resolve(probe as MinecraftProbe);
    };
    const timeout = setTimeout(() => finish(new Error("Minecraft status probe timed out.")), timeoutMs);

    socket.once("connect", () => socket.write(minecraftStatusPacket(host, port)));
    socket.on("error", (error) => finish(error));
    socket.on("data", (chunk: Buffer) => {
      received = Buffer.concat([received, chunk]);
      try {
        const frame = decodeVarInt(received);
        if (!frame || received.length < frame.size + frame.value) return;
        const payload = received.subarray(frame.size, frame.size + frame.value);
        const packetId = decodeVarInt(payload);
        if (!packetId || packetId.value !== 0) throw new Error("Unexpected Minecraft status response.");
        const jsonLength = decodeVarInt(payload, packetId.size);
        if (!jsonLength || payload.length < packetId.size + jsonLength.size + jsonLength.value) return;
        const jsonStart = packetId.size + jsonLength.size;
        const status = JSON.parse(payload.subarray(jsonStart, jsonStart + jsonLength.value).toString("utf8"));
        finish(undefined, {
          playersOnline: Number(status.players?.online ?? 0),
          playersMax: Number(status.players?.max ?? 0),
        });
      } catch (error) {
        finish(error instanceof Error ? error : new Error("Invalid Minecraft status response."));
      }
    });
  });

const describeServerHealth = async (server: MinecraftServer): Promise<string> => {
  if (server.state !== "running") return describeServer(server);
  const address = server.publicIp ? `${server.publicIp}:${server.port}` : "address unavailable";
  if (!server.publicIp) return `🟡 **${server.name}** — ${address} — starting`;
  try {
    const probe = await probeMinecraft(server.publicIp, server.port);
    const uptime = formatUptime(server.launchedAt);
    const uptimeText = uptime ? ` — up ${uptime}` : "";
    return `🟢 **${server.name}** — ${address} — ${probe.playersOnline}/${probe.playersMax} online${uptimeText}`;
  } catch {
    return `🟡 **${server.name}** — ${address} — starting or unreachable`;
  }
};

export const resolveServer = (
  servers: MinecraftServer[],
  key: string,
): MinecraftServer => {
  const matches = servers.filter((server) => server.key === key);
  if (matches.length === 0) throw new Error(`Unknown server: ${key}`);
  if (matches.length > 1) throw new Error(`Duplicate MinecraftServer tag: ${key}`);
  return matches[0];
};

export const recordOnce = async (put: () => Promise<unknown>): Promise<boolean> => {
  try {
    await put();
    return true;
  } catch (error) {
    if (error instanceof Error && error.name === "ConditionalCheckFailedException") {
      return false;
    }
    throw error;
  }
};

const recordInteraction = async (interactionId: string): Promise<boolean> => {
  if (!INTERACTION_TABLE) throw new Error("Missing DISCORD_INTERACTION_TABLE.");
  const expiresAt = Math.floor(Date.now() / 1000) + INTERACTION_TTL_SECONDS;
  return recordOnce(() =>
    dynamoClient.send(
      new PutItemCommand({
        TableName: INTERACTION_TABLE,
        Item: {
          interaction_id: { S: interactionId },
          expires_at: { N: String(expiresAt) },
        },
        ConditionExpression: "attribute_not_exists(interaction_id)",
      }),
    ),
  );
};

const handleAutocomplete = async (data: {
  options?: DiscordOption[];
}): Promise<APIGatewayProxyResult> => {
  const query = String(
    findOption(data.options, (option) => option.focused === true)?.value ?? "",
  ).toLowerCase();
  const choices = (await listServers())
    .filter(
      (server) =>
        server.key.toLowerCase().includes(query) ||
        server.name.toLowerCase().includes(query),
    )
    .slice(0, 25)
    .map((server) => ({
      name: server.publicIp ? `${server.name} — ${server.publicIp}:${server.port}` : server.name,
      value: server.key,
    }));

  return {
    statusCode: 200,
    body: JSON.stringify({
      type: InteractionResponseType.APPLICATION_COMMAND_AUTOCOMPLETE_RESULT,
      data: { choices },
    }),
  };
};

const stopServerGracefully = async (server: MinecraftServer): Promise<void> => {
  await ssmClient.send(
    new SendCommandCommand({
      DocumentName: "AWS-RunShellScript",
      InstanceIds: [server.instanceId],
      Comment: `Discord graceful shutdown for ${server.key}`,
      TimeoutSeconds: 900,
      Parameters: {
        commands: [
          "set -euo pipefail",
          "systemctl stop minecraft.service",
          "sync",
          "shutdown -h now",
        ],
      },
    }),
  );
};

const handleCommand = async (data: {
  name?: string;
  options?: DiscordOption[];
}): Promise<APIGatewayProxyResult> => {
  const action = data.name;
  const selected = findOption(data.options, (option) => option.name === "server");
  const servers = await listServers();

  if (action === "status") {
    return servers.length === 0
      ? response("No managed Minecraft servers were found.")
      : response((await Promise.all(servers.map(describeServerHealth))).join("\n"));
  }
  if (!action || !["start", "stop", "status"].includes(action)) {
    return response(`Unknown command: ${action ?? "missing"}`);
  }

  if (!selected?.value) return response("Choose a server from the search results.");
  const requestedKey = String(selected.value);

  const server = resolveServer(servers, requestedKey);

  if (action === "start") {
    if (["running", "pending"].includes(server.state)) {
      return response(`⚠️ **${server.name}** is already ${server.state}.`);
    }
    if (["stopping", "shutting-down"].includes(server.state)) {
      return response(`⚠️ **${server.name}** is ${server.state}; wait before starting it.`);
    }
    await ec2Client.send(new StartInstancesCommand({ InstanceIds: [server.instanceId] }));
    // A stopped instance can receive a different public IP after it starts.
    // Refresh EC2 metadata so the start response gives the player the address
    // to use instead of relying on the stale instance list from above.
    const refreshedServer = (await listServers()).find(
      (candidate) => candidate.instanceId === server.instanceId,
    );
    const address = refreshedServer?.publicIp
      ? `${refreshedServer.publicIp}:${refreshedServer.port}`
      : "address pending — run /status again shortly";
    return response(`✅ **${server.name}** is starting. Connect at **${address}**.`);
  }

  if (["stopped", "stopping", "shutting-down"].includes(server.state)) {
    return response(`⚠️ **${server.name}** is already ${server.state}.`);
  }
  if (server.state === "pending") {
    return response(`⚠️ **${server.name}** is pending; wait before stopping it.`);
  }
  await stopServerGracefully(server);
  return response(`🛑 **${server.name}** is stopping gracefully…`);
};

export const hasFreshTimestamp = (timestamp: string, nowMs = Date.now()): boolean => {
  const seconds = Number(timestamp);
  return Number.isFinite(seconds) &&
    Math.abs(Math.floor(nowMs / 1000) - seconds) <= MAX_INTERACTION_AGE_SECONDS;
};

export const handler = async (
  event: APIGatewayProxyEvent,
): Promise<APIGatewayProxyResult> => {
  if (!DISCORD_PUBLIC_KEY) return { statusCode: 500, body: "Missing Discord public key" };

  const signature = event.headers["x-signature-ed25519"] ?? "";
  const timestamp = event.headers["x-signature-timestamp"] ?? "";
  const body = event.body ?? "";
  if (!hasFreshTimestamp(timestamp) || !await verifyKey(body, signature, timestamp, DISCORD_PUBLIC_KEY)) {
    return { statusCode: 401, body: "Invalid or expired request signature" };
  }

  const interaction = JSON.parse(body);
  if (interaction.type === InteractionType.PING) {
    return { statusCode: 200, body: JSON.stringify({ type: InteractionResponseType.PONG }) };
  }
  if (ALLOWED_GUILD_ID && interaction.guild_id !== ALLOWED_GUILD_ID) {
    return response("This bot is not enabled in this Discord server.");
  }

  try {
    if (interaction.type === InteractionType.APPLICATION_COMMAND_AUTOCOMPLETE) {
      return await handleAutocomplete(interaction.data ?? {});
    }
    if (interaction.type !== InteractionType.APPLICATION_COMMAND) {
      return response("Unsupported interaction type.");
    }
    if (!interaction.id || !await recordInteraction(interaction.id)) {
      return response("This interaction was already processed.");
    }

    console.log(JSON.stringify({
      interactionId: interaction.id,
      guildId: interaction.guild_id,
      userId: interaction.member?.user?.id ?? interaction.user?.id,
      command: interaction.data?.name,
    }));
    return await handleCommand(interaction.data ?? {});
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Error handling Discord interaction", error);
    return response(`❌ ${message}`);
  }
};
