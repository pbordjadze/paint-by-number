// Tests of the relay's ballots (votes.js), with the schedule and the Durable Objects faked.
// `node --test feedback-relay/votes.test.js`; CI's `core` job runs it.

import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";

import { handle } from "./worker.js";
import { Ballot, forgetSchedule } from "./votes.js";

const NIGHTS_URL = "https://example.test/nights.json";
const SCHEDULE = {
  format: 1,
  ballots: [
    { night: "2026-11-22", opens: "2026-11-20T08:00:00Z", closes: "2026-11-21T08:00:00Z", choices: ["aic-1", "cma-2", "aic-3"] },
    { night: "2026-11-23", opens: "2026-11-21T08:00:00Z", closes: "2026-11-22T08:00:00Z", choices: ["aic-4", "cma-5", "aic-6"] },
  ],
};
const OPEN = new Date("2026-11-21T01:00:00Z");

/** Durable Objects in memory: one Ballot a name, each with a Map for storage. */
function ballots() {
  const objects = new Map();
  return {
    idFromName: (name) => name,
    get(id) {
      if (!objects.has(id)) {
        const map = new Map();
        const storage = { get: async (k) => structuredClone(map.get(k)), put: async (k, v) => void map.set(k, structuredClone(v)) };
        objects.set(id, new Ballot({ storage }));
      }
      const object = objects.get(id);
      return { fetch: (url, init) => object.fetch(new Request(url, init)) };
    },
  };
}

let env;
let fetches;
const deps = (now = OPEN) => ({
  now,
  fetch: async (url) => {
    fetches += 1;
    assert.equal(url, NIGHTS_URL);
    return new Response(JSON.stringify(SCHEDULE), { status: 200 });
  },
});

beforeEach(() => {
  forgetSchedule();
  fetches = 0;
  env = { BALLOTS: ballots(), NIGHTS_URL };
});

function vote(body, { type = "application/json", ip = "1.2.3.4" } = {}) {
  return new Request("https://relay.test/v1/votes", {
    method: "POST",
    headers: { "content-type": type, "cf-connecting-ip": ip },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const tally = (night, now) => handle(new Request(`https://relay.test/v1/ballots/${night}`), env, deps(now));

test("a vote on an open ballot counts, and the tally shows it once the ballot closes", async () => {
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "cma-2" }), env, deps())).status, 201);
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "cma-2" }), env, deps())).status, 201);
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-1" }), env, deps())).status, 201);
  assert.equal((await tally("2026-11-22", OPEN)).status, 409, "no tally while the ballot is open");
  const closed = await tally("2026-11-22", new Date("2026-11-21T08:00:00Z"));
  assert.equal(closed.status, 200);
  assert.deepEqual(await closed.json(), { night: "2026-11-22", votes: { "cma-2": 2, "aic-1": 1 } });
  assert.equal(fetches, 1, "the schedule is read once in five minutes");
});

test("a ballot not yet open, closed, or unknown takes no vote", async () => {
  assert.equal((await handle(vote({ night: "2026-11-23", choice: "aic-4" }), env, deps())).status, 409);
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-1" }), env, deps(new Date("2026-11-21T08:00:00Z")))).status, 409);
  assert.equal((await handle(vote({ night: "2026-12-01", choice: "aic-1" }), env, deps())).status, 409);
});

test("a choice the ballot doesn't offer is refused", async () => {
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-4" }), env, deps())).status, 409);
});

test("malformed votes are refused", async () => {
  assert.equal((await handle(vote("not json"), env, deps())).status, 400);
  assert.equal((await handle(vote({ night: "22 Nov", choice: "aic-1" }), env, deps())).status, 400);
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "../x" }), env, deps())).status, 400);
  assert.equal((await handle(vote({ night: "2026-11-22" }), env, deps())).status, 400);
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-1" }, { type: "text/plain" }), env, deps())).status, 415);
  assert.equal((await handle(vote("x".repeat(2000)), env, deps())).status, 413);
});

test("methods and paths", async () => {
  assert.equal((await handle(new Request("https://relay.test/v1/votes"), env, deps())).status, 405);
  assert.equal((await handle(new Request("https://relay.test/v1/ballots/2026-11-22", { method: "POST" }), env, deps())).status, 405);
  assert.equal((await tally("nonsense", OPEN)).status, 404);
});

test("the rate limiter turns a flood away", async () => {
  env.VOTE_LIMITER = { limit: async () => ({ success: false }) };
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-1" }), env, deps())).status, 429);
});

test("an unreadable schedule is a 502, and a relay without its bindings a 500", async () => {
  const failing = { now: OPEN, fetch: async () => new Response("", { status: 503 }) };
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-1" }), env, failing)).status, 502);
  assert.equal((await handle(vote({ night: "2026-11-22", choice: "aic-1" }), {}, deps())).status, 500);
});
