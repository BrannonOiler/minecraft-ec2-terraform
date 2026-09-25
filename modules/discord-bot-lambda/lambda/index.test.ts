import assert from "node:assert/strict";
import test from "node:test";
import {
  describeServer,
  formatUptime,
  handler,
  hasFreshTimestamp,
  portFromTag,
  probeMinecraft,
  recordOnce,
  resolveServer,
} from "./index";

test("retains the Lambda handler and existing helper exports", () => {
  assert.equal(typeof handler, "function");
  for (const exported of [
    describeServer,
    formatUptime,
    hasFreshTimestamp,
    portFromTag,
    probeMinecraft,
    recordOnce,
    resolveServer,
  ]) {
    assert.equal(typeof exported, "function");
  }
});
