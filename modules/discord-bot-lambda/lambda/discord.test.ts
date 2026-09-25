import type { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import assert from "node:assert/strict";
import test from "node:test";
import {
  createInteractionHandler,
  hasFreshTimestamp,
  response,
} from "./discord";

const event = (
  body: Record<string, unknown>,
  timestamp = String(Math.floor(Date.now() / 1000)),
): APIGatewayProxyEvent => ({
  body: JSON.stringify(body),
  headers: {
    "x-signature-ed25519": "signature",
    "x-signature-timestamp": timestamp,
  },
} as unknown as APIGatewayProxyEvent);

const createHandler = (overrides: Partial<Parameters<
  typeof createInteractionHandler
>[0]> = {}) => createInteractionHandler({
  publicKey: "public-key",
  allowedGuildId: "12345678901234567",
  verifyRequest: async () => true,
  recordInteraction: async () => true,
  handleAutocomplete: async () => response("autocomplete"),
  handleCommand: async () => response("command"),
  ...overrides,
});

const content = (result: APIGatewayProxyResult): string =>
  JSON.parse(result.body).data.content;

test("accepts fresh timestamps and rejects stale timestamps", () => {
  assert.equal(hasFreshTimestamp("1000", 1000 * 1000), true);
  assert.equal(hasFreshTimestamp("1000", 1301 * 1000), false);
});

test("rejects missing keys and invalid or expired signatures", async () => {
  const missingKey = createHandler({ publicKey: undefined });
  assert.deepEqual(await missingKey(event({ type: 1 })), {
    statusCode: 500,
    body: "Missing Discord public key",
  });

  let verified = false;
  const stale = createHandler({
    verifyRequest: async () => { verified = true; return true; },
  });
  const result = await stale(event({ type: 1 }, "0"));
  assert.equal(result.statusCode, 401);
  assert.equal(verified, false);

  const invalid = createHandler({ verifyRequest: async () => false });
  assert.equal((await invalid(event({ type: 1 }))).statusCode, 401);
});

test("responds to pings before enforcing the guild restriction", async () => {
  const result = await createHandler()(event({ type: 1, guild_id: "other" }));
  assert.deepEqual(JSON.parse(result.body), { type: 1 });
});

test("rejects other guilds and unsupported interaction types", async () => {
  const handler = createHandler();
  assert.equal(
    content(await handler(event({ type: 2, guild_id: "other" }))),
    "This bot is not enabled in this Discord server.",
  );
  assert.equal(
    content(await handler(event({
      type: 99,
      guild_id: "12345678901234567",
    }))),
    "Unsupported interaction type.",
  );
});

test("routes autocomplete without recording an interaction", async () => {
  let recorded = false;
  const handler = createHandler({
    recordInteraction: async () => { recorded = true; return true; },
  });
  assert.equal(content(await handler(event({
    type: 4,
    guild_id: "12345678901234567",
  }))), "autocomplete");
  assert.equal(recorded, false);
});

test("rejects duplicate commands and formats command errors", async (context) => {
  context.mock.method(console, "log", () => undefined);
  context.mock.method(console, "error", () => undefined);
  const duplicate = createHandler({ recordInteraction: async () => false });
  assert.equal(content(await duplicate(event({
    id: "interaction",
    type: 2,
    guild_id: "12345678901234567",
  }))), "This interaction was already processed.");

  const failing = createHandler({
    handleCommand: async () => { throw new Error("AWS unavailable"); },
  });
  assert.equal(content(await failing(event({
    id: "interaction",
    type: 2,
    guild_id: "12345678901234567",
  }))), "❌ AWS unavailable");
});
