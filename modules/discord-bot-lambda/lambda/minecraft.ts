import type { Instance, InstanceStateName } from "@aws-sdk/client-ec2";
import net from "node:net";

const STATUS_PROBE_TIMEOUT_MS = 1500;

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

export type MinecraftProbe = {
  playersOnline: number;
  playersMax: number;
};

const tagValue = (instance: Instance, key: string): string | undefined =>
  instance.Tags?.find((tag) => tag.Key === key)?.Value;

export const portFromTag = (instance: Instance): number => {
  const parsed = Number(tagValue(instance, "MinecraftPort") ?? "25565");
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 65535
    ? parsed
    : 25565;
};

export const serverFromInstance = (instance: Instance): MinecraftServer => ({
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
});

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

export const formatUptime = (
  launchedAt: number | undefined,
  now = Date.now(),
): string => {
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

const decodeVarInt = (
  buffer: Buffer,
  offset = 0,
): { value: number; size: number } | undefined => {
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

export const parseMinecraftStatusResponse = (
  received: Buffer,
): MinecraftProbe | undefined => {
  const frame = decodeVarInt(received);
  if (!frame || received.length < frame.size + frame.value) return undefined;

  const payload = received.subarray(frame.size, frame.size + frame.value);
  const packetId = decodeVarInt(payload);
  if (!packetId || packetId.value !== 0) {
    throw new Error("Unexpected Minecraft status response.");
  }

  const jsonLength = decodeVarInt(payload, packetId.size);
  if (
    !jsonLength ||
    payload.length < packetId.size + jsonLength.size + jsonLength.value
  ) {
    return undefined;
  }

  const jsonStart = packetId.size + jsonLength.size;
  const status = JSON.parse(
    payload
      .subarray(jsonStart, jsonStart + jsonLength.value)
      .toString("utf8"),
  ) as { players?: { online?: unknown; max?: unknown } };
  return {
    playersOnline: Number(status.players?.online ?? 0),
    playersMax: Number(status.players?.max ?? 0),
  };
};

export const probeMinecraft = (
  host: string,
  port: number,
  timeoutMs = STATUS_PROBE_TIMEOUT_MS,
): Promise<MinecraftProbe> =>
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
      else if (probe) resolve(probe);
    };
    const timeout = setTimeout(
      () => finish(new Error("Minecraft status probe timed out.")),
      timeoutMs,
    );

    socket.once("connect", () => socket.write(minecraftStatusPacket(host, port)));
    socket.on("error", (error) => finish(error));
    socket.on("data", (chunk: Buffer) => {
      received = Buffer.concat([received, chunk]);
      try {
        const probe = parseMinecraftStatusResponse(received);
        if (probe) finish(undefined, probe);
      } catch (error) {
        finish(
          error instanceof Error
            ? error
            : new Error("Invalid Minecraft status response."),
        );
      }
    });
  });

export const describeServerHealth = async (
  server: MinecraftServer,
  probe: typeof probeMinecraft = probeMinecraft,
): Promise<string> => {
  if (server.state !== "running") return describeServer(server);
  const address = server.publicIp
    ? `${server.publicIp}:${server.port}`
    : "address unavailable";
  if (!server.publicIp) {
    return `🟡 **${server.name}** — ${address} — starting`;
  }
  try {
    const status = await probe(server.publicIp, server.port);
    const uptime = formatUptime(server.launchedAt);
    const uptimeText = uptime ? ` — up ${uptime}` : "";
    return `🟢 **${server.name}** — ${address} — ${status.playersOnline}/${status.playersMax} online${uptimeText}`;
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
  if (matches.length > 1) {
    throw new Error(`Duplicate MinecraftServer tag: ${key}`);
  }
  return matches[0];
};
