// Tonight's Picture's ballots (painting-company row 368): the relay counts the painters' votes for a
// coming night's picture. worker.js routes /v1/votes and /v1/ballots/ here; tested by
// `node --test feedback-relay/votes.test.js`.
//
//   POST /v1/votes          {"night": "2026-11-22", "choice": "<picture id>"}, application/json,
//                           at most 1 KB. Counted when that night's ballot in the schedule
//                           (NIGHTS_URL, the nights branch's nights.json, read at most every five
//                           minutes) is open now and offers the choice. 201 {"ok":true}; 400 a
//                           malformed body; 409 no such ballot open, or not one of its choices;
//                           413 too large; 415 not JSON; 429 over the rate limit; 502 the schedule
//                           can't be read.
//   GET  /v1/ballots/<date> {"night", "votes": {"<picture id>": n}} once the ballot has closed, for
//                           the Nights workflow's tally (tools/nights/publish.py); 409 while open,
//                           404 a malformed date or one closed more than 40 days ago.
//
// No painter is identified: a vote is a night, a choice and a count. The app keeps one vote a
// ballot itself; the relay brakes floods per address (VOTE_LIMITER, wrangler.toml) and never
// learns more than the count. Each night's count lives in its own Durable Object (Ballot,
// SQLite-backed, named by the date), whose storage operations are atomic, so counts never race.

const VOTES_PATH = "/v1/votes";
const BALLOTS_PREFIX = "/v1/ballots/";
const MAX_VOTE = 1024;
const SCHEDULE_TTL = 300;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^[a-z0-9]+(-[a-z0-9]+)*$/;

export function routesVotes(pathname) {
  return pathname === VOTES_PATH || pathname.startsWith(BALLOTS_PREFIX);
}

export async function handleVotes(request, env, deps = {}) {
  const url = new URL(request.url);
  const now = deps.now ?? new Date();
  if (url.pathname === VOTES_PATH) {
    if (request.method !== "POST") return bare(405, { allow: "POST" });
    return vote(request, env, now, deps);
  }
  if (request.method !== "GET") return bare(405, { allow: "GET" });
  return ballot(url.pathname.slice(BALLOTS_PREFIX.length), env, now, deps);
}

async function vote(request, env, now, deps) {
  if (!env.BALLOTS || !env.NIGHTS_URL) return bare(500);
  if (!(await allowed(env.VOTE_LIMITER, request.headers.get("cf-connecting-ip") ?? "unknown"))) return bare(429);
  if (!/^application\/json\b/i.test(request.headers.get("content-type") ?? "")) return bare(415);
  const length = request.headers.get("content-length");
  if (length !== null && Number(length) > MAX_VOTE) return bare(413);
  const text = await readCapped(request, MAX_VOTE);
  if (text === null) return bare(413);
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return bare(400);
  }
  if (typeof body?.night !== "string" || !DATE.test(body.night) || typeof body?.choice !== "string" || !ID.test(body.choice)) {
    return bare(400);
  }
  let schedule;
  try {
    schedule = await readSchedule(env, deps);
  } catch (error) {
    console.error(`Reading the schedule failed: ${error instanceof Error ? error.message : String(error)}`);
    return bare(502);
  }
  const open = (schedule.ballots ?? []).find((b) => b.night === body.night);
  if (!open || !(Date.parse(open.opens) <= now.getTime() && now.getTime() < Date.parse(open.closes))) return bare(409);
  if (!Array.isArray(open.choices) || !open.choices.includes(body.choice)) return bare(409);
  const added = await stub(env, body.night).fetch("https://ballot/add", { method: "POST", body: body.choice });
  if (!added.ok) return bare(502);
  return json(201, { ok: true });
}

async function ballot(night, env, now, deps) {
  if (!DATE.test(night)) return bare(404);
  if (!env.BALLOTS) return bare(500);
  // A ballot closes at 08:00 UTC on the day before its night (publish.py's CLOSE_HOUR).
  const closes = Date.parse(`${night}T08:00:00Z`) - 24 * 3600 * 1000;
  if (Number.isNaN(closes)) return bare(404);
  if (now.getTime() < closes) return bare(409);
  // Only the nights a schedule could have held: the last 40 days.
  if (now.getTime() - closes > 40 * 24 * 3600 * 1000) return bare(404);
  const votes = await (await stub(env, night).fetch("https://ballot/counts")).json();
  return json(200, { night, votes });
}

function stub(env, night) {
  return env.BALLOTS.get(env.BALLOTS.idFromName(night));
}

/** The body as text, or null once it passes `limit` bytes (read no further, chunked or not). */
async function readCapped(request, limit) {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

let cached = null;

async function readSchedule(env, deps) {
  const now = (deps.now ?? new Date()).getTime();
  if (cached && cached.url === env.NIGHTS_URL && now - cached.at < SCHEDULE_TTL * 1000) return cached.schedule;
  const fetcher = deps.fetch ?? fetch;
  const response = await fetcher(env.NIGHTS_URL, { cf: { cacheTtl: SCHEDULE_TTL } });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const schedule = await response.json();
  cached = { url: env.NIGHTS_URL, at: now, schedule };
  return schedule;
}

/** Forgets the schedule read last (the tests). */
export function forgetSchedule() {
  cached = null;
}

async function allowed(limiter, key) {
  if (!limiter) return true;
  try {
    return (await limiter.limit({ key })).success;
  } catch {
    return true;
  }
}

function bare(status, headers) {
  return new Response(null, { status, headers });
}

function json(status, value) {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
}

/**
 * One night's ballot, a Durable Object named by its date: the count of each choice. Its input
 * gate holds other requests while one reads and writes its storage, so votes never race.
 *   POST https://ballot/add      the choice as the body
 *   GET  https://ballot/counts   {"<choice>": n}
 */
export class Ballot {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/add" && request.method === "POST") {
      const choice = await request.text();
      if (!ID.test(choice)) return bare(400);
      const votes = (await this.storage.get("votes")) ?? {};
      votes[choice] = (votes[choice] ?? 0) + 1;
      await this.storage.put("votes", votes);
      return json(201, { ok: true });
    }
    if (pathname === "/counts" && request.method === "GET") return json(200, (await this.storage.get("votes")) ?? {});
    return bare(404);
  }
}
