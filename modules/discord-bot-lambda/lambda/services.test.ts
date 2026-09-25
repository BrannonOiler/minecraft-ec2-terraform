import assert from "node:assert/strict";
import test from "node:test";
import { recordOnce } from "./services";

test("treats a conditional DynamoDB write failure as a replay", async () => {
  const replay = new Error("already seen");
  replay.name = "ConditionalCheckFailedException";
  assert.equal(await recordOnce(async () => undefined), true);
  assert.equal(await recordOnce(async () => { throw replay; }), false);
});

test("rethrows non-conditional DynamoDB failures", async () => {
  await assert.rejects(
    recordOnce(async () => { throw new Error("unavailable"); }),
    /unavailable/,
  );
});
