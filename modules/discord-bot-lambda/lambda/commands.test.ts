import assert from "node:assert/strict";
import test from "node:test";
import { createCommandHandlers } from "./commands";
import { MinecraftServer } from "./minecraft";

const server = (overrides: Partial<MinecraftServer> = {}): MinecraftServer => ({
  key: "homestead",
  name: "Homestead",
  instanceId: "i-123",
  publicIp: "203.0.113.10",
  port: 25565,
  profile: "homestead-1-2-9-4",
  state: "stopped",
  ...overrides,
});

const content = (body: string): string => JSON.parse(body).data.content;

test("filters autocomplete choices and limits the response to 25", async () => {
  const servers = Array.from({ length: 30 }, (_, index) => server({
    key: `vanilla-${index}`,
    name: `Vanilla ${index}`,
  }));
  const handlers = createCommandHandlers({
    listServers: async () => servers,
    startServer: async () => undefined,
    stopServerGracefully: async () => undefined,
  });
  const result = await handlers.handleAutocomplete({
    options: [{ name: "server", value: "vanilla", focused: true }],
  });
  const payload = JSON.parse(result.body);
  assert.equal(payload.data.choices.length, 25);
  assert.deepEqual(payload.data.choices[0], {
    name: "Vanilla 0 — 203.0.113.10:25565",
    value: "vanilla-0",
  });
});

test("reports empty and populated fleet status", async () => {
  const empty = createCommandHandlers({
    listServers: async () => [],
    startServer: async () => undefined,
    stopServerGracefully: async () => undefined,
  });
  assert.equal(
    content((await empty.handleCommand({ name: "status" })).body),
    "No managed Minecraft servers were found.",
  );

  const populated = createCommandHandlers({
    listServers: async () => [server()],
    startServer: async () => undefined,
    stopServerGracefully: async () => undefined,
    describeHealth: async (target) => `health:${target.key}`,
  });
  assert.equal(
    content((await populated.handleCommand({ name: "status" })).body),
    "health:homestead",
  );
});

test("starts a stopped server and preserves the connection response", async () => {
  let started: MinecraftServer | undefined;
  const handlers = createCommandHandlers({
    listServers: async () => [server()],
    startServer: async (target) => { started = target; },
    stopServerGracefully: async () => undefined,
  });
  const result = await handlers.handleCommand({
    name: "start",
    options: [{ name: "server", value: "homestead" }],
  });
  assert.equal(started?.instanceId, "i-123");
  assert.equal(
    content(result.body),
    "✅ **Homestead** is starting. Connect at **203.0.113.10:25565**.",
  );
});

test("preserves start and stop transition guards", async () => {
  let stopCalls = 0;
  const handlersFor = (state: MinecraftServer["state"]) =>
    createCommandHandlers({
      listServers: async () => [server({ state })],
      startServer: async () => undefined,
      stopServerGracefully: async () => { stopCalls += 1; },
    });

  assert.match(content((await handlersFor("running").handleCommand({
    name: "start",
    options: [{ name: "server", value: "homestead" }],
  })).body), /already running/);
  assert.match(content((await handlersFor("stopping").handleCommand({
    name: "start",
    options: [{ name: "server", value: "homestead" }],
  })).body), /wait before starting/);
  assert.match(content((await handlersFor("pending").handleCommand({
    name: "stop",
    options: [{ name: "server", value: "homestead" }],
  })).body), /wait before stopping/);
  assert.match(content((await handlersFor("stopped").handleCommand({
    name: "stop",
    options: [{ name: "server", value: "homestead" }],
  })).body), /already stopped/);
  assert.equal(stopCalls, 0);
});

test("gracefully stops a running server and propagates service errors", async () => {
  let stopped = false;
  const handlers = createCommandHandlers({
    listServers: async () => [server({ state: "running" })],
    startServer: async () => undefined,
    stopServerGracefully: async () => { stopped = true; },
  });
  const result = await handlers.handleCommand({
    name: "stop",
    options: [{ name: "server", value: "homestead" }],
  });
  assert.equal(stopped, true);
  assert.equal(content(result.body), "🛑 **Homestead** is stopping gracefully…");

  const failing = createCommandHandlers({
    listServers: async () => { throw new Error("AWS unavailable"); },
    startServer: async () => undefined,
    stopServerGracefully: async () => undefined,
  });
  await assert.rejects(failing.handleCommand({ name: "status" }), /AWS unavailable/);
});
