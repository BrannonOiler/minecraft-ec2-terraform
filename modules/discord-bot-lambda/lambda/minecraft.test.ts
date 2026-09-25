import { Instance } from "@aws-sdk/client-ec2";
import assert from "node:assert/strict";
import net from "node:net";
import test from "node:test";
import {
  describeServer,
  describeServerHealth,
  formatUptime,
  MinecraftServer,
  parseMinecraftStatusResponse,
  portFromTag,
  probeMinecraft,
  resolveServer,
} from "./minecraft";

const server = (overrides: Partial<MinecraftServer> = {}): MinecraftServer => ({
  key: "homestead",
  name: "Homestead",
  instanceId: "i-123",
  port: 25565,
  profile: "homestead-1-2-9-4",
  state: "stopped",
  ...overrides,
});

const statusFrame = (online: number, maximum: number): Buffer => {
  const json = Buffer.from(JSON.stringify({
    players: { online, max: maximum },
  }));
  const payload = Buffer.concat([Buffer.from([0, json.length]), json]);
  return Buffer.concat([Buffer.from([payload.length]), payload]);
};

test("uses the tagged Minecraft port in simple fleet status", () => {
  const instance: Instance = {
    Tags: [{ Key: "MinecraftPort", Value: "25566" }],
  };
  assert.equal(portFromTag(instance), 25566);
  const description = describeServer(server({
    key: "vanilla",
    name: "Vanilla",
    publicIp: "203.0.113.10",
    port: 25566,
    profile: "vanilla-1-21",
    state: "running",
  }));
  assert.match(description, /203\.0\.113\.10:25566/);
  assert.doesNotMatch(description, /vanilla-1-21/);
});

test("formats instance uptime for live server status", () => {
  assert.equal(formatUptime(0, 65 * 60 * 1000), "1h 5m");
  assert.equal(formatUptime(undefined), "");
});

test("rejects invalid ports and unknown or duplicate server keys", () => {
  assert.equal(
    portFromTag({ Tags: [{ Key: "MinecraftPort", Value: "0" }] }),
    25565,
  );
  const servers = [server()];
  assert.equal(resolveServer(servers, "homestead").instanceId, "i-123");
  assert.throws(() => resolveServer(servers, "missing"), /Unknown server/);
  assert.throws(
    () => resolveServer([...servers, servers[0]], "homestead"),
    /Duplicate/,
  );
});

test("parses complete status packets and waits for partial packets", () => {
  const frame = statusFrame(2, 8);
  assert.deepEqual(parseMinecraftStatusResponse(frame), {
    playersOnline: 2,
    playersMax: 8,
  });
  assert.equal(parseMinecraftStatusResponse(frame.subarray(0, 3)), undefined);
  assert.throws(
    () => parseMinecraftStatusResponse(Buffer.from([1, 1])),
    /Unexpected Minecraft status response/,
  );
  assert.throws(
    () => parseMinecraftStatusResponse(Buffer.from([3, 0, 1, 123])),
    /JSON/,
  );
});

test("times out when a Minecraft endpoint never returns status", async () => {
  const endpoint = net.createServer(() => undefined);
  await new Promise<void>((resolve) => endpoint.listen(0, "127.0.0.1", resolve));
  const address = endpoint.address();
  assert.ok(address && typeof address !== "string");
  try {
    await assert.rejects(
      probeMinecraft("127.0.0.1", address.port, 25),
      /timed out/,
    );
  } finally {
    endpoint.close();
  }
});

test("reports running server health and unreachable fallback text", async () => {
  const running = server({
    publicIp: "203.0.113.10",
    state: "running",
    launchedAt: 0,
  });
  assert.match(
    await describeServerHealth(running, async () => ({
      playersOnline: 1,
      playersMax: 4,
    })),
    /1\/4 online/,
  );
  assert.match(
    await describeServerHealth(running, async () => {
      throw new Error("offline");
    }),
    /starting or unreachable/,
  );
});
