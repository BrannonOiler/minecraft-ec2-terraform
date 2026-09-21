import assert from "node:assert/strict";
import test from "node:test";
import { Instance } from "@aws-sdk/client-ec2";
import {
  describeServer,
  formatUptime,
  hasFreshTimestamp,
  portFromTag,
  recordOnce,
  resolveServer,
} from "./index";

test("uses the tagged Minecraft port in simple fleet status", () => {
  const instance: Instance = { Tags: [{ Key: "MinecraftPort", Value: "25566" }] };
  assert.equal(portFromTag(instance), 25566);
  assert.match(
    describeServer({
      key: "vanilla",
      name: "Vanilla",
      instanceId: "i-123",
      publicIp: "203.0.113.10",
      port: 25566,
      profile: "vanilla-1-21",
      state: "running",
    }),
    /203\.0\.113\.10:25566/,
  );
  assert.doesNotMatch(
    describeServer({
      key: "vanilla",
      name: "Vanilla",
      instanceId: "i-123",
      publicIp: "203.0.113.10",
      port: 25566,
      profile: "vanilla-1-21",
      state: "running",
    }),
    /vanilla-1-21/,
  );
});

test("formats instance uptime for live server status", () => {
  assert.equal(formatUptime(0, 65 * 60 * 1000), "1h 5m");
  assert.equal(formatUptime(undefined), "");
});

test("rejects invalid ports and stale interaction timestamps", () => {
  assert.equal(portFromTag({ Tags: [{ Key: "MinecraftPort", Value: "0" }] }), 25565);
  assert.equal(hasFreshTimestamp("1000", 1000 * 1000), true);
  assert.equal(hasFreshTimestamp("1000", 1301 * 1000), false);
});

test("rejects unknown or duplicate server keys", () => {
  const servers = [{
    key: "homestead",
    name: "Homestead",
    instanceId: "i-123",
    port: 25565,
    profile: "homestead-1-2-9-4",
    state: "stopped" as const,
  }];
  assert.equal(resolveServer(servers, "homestead").instanceId, "i-123");
  assert.throws(() => resolveServer(servers, "missing"), /Unknown server/);
  assert.throws(() => resolveServer([...servers, servers[0]], "homestead"), /Duplicate/);
});

test("treats a conditional DynamoDB write failure as a replay", async () => {
  const replay = new Error("already seen");
  replay.name = "ConditionalCheckFailedException";
  assert.equal(await recordOnce(async () => undefined), true);
  assert.equal(await recordOnce(async () => { throw replay; }), false);
});
