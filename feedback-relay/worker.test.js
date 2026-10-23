// Tests of the feedback relay against a mocked GitHub (a small fake of the parts of its API the
// worker uses). `node --test feedback-relay/worker.test.js`; CI's `core` job runs it, on Node 18 too.

import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { webcrypto } from "node:crypto";
import { afterEach, beforeEach, test } from "node:test";

import worker, { handle } from "./worker.js";

globalThis.crypto ??= webcrypto;

const REPO = "pbordjadze/paint-feedback";
const TOKEN = "github_pat_SECRET_TOKEN_VALUE";
const ENV = { FEEDBACK_REPO: REPO, FEEDBACK_GITHUB_TOKEN: TOKEN };
const NOW = new Date("2026-10-16T09:08:07.123Z");
const FOLDER = "reports/2026-10-16/090807-a1b2c3";
const DEPS = { now: NOW, randomHex: () => "a1b2c3" };

const PNG = Uint8Array.of(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4);
const ZIP = Uint8Array.of(0x50, 0x4b, 0x03, 0x04, 9, 8, 7, 6, 5);
const REPORT = "# Red Fox: feedback\n\nPaint by Moonlight 1.0 (7) on iPad16,6\n\n## Note\n\nToo fiddly.\n";
const PICTURE_NAME = "Red Fox Feedback 2026-10-05 14.32.png";
const BUNDLE_NAME = "Red Fox Feedback 2026-10-05 14.32.zip";

// MARK: Helpers

/** A request as the app sends it. `parts` replace the default ones; `null` leaves a part out. */
async function feedback({ parts = {}, headers = {}, method = "POST", path = "/v1/feedback", length } = {}) {
  const defaults = {
    report: [new Blob([REPORT], { type: "text/markdown; charset=utf-8" }), "feedback.md"],
    picture: [new Blob([PNG], { type: "image/png" }), PICTURE_NAME],
    bundle: [new Blob([ZIP], { type: "application/zip" }), BUNDLE_NAME],
  };
  const form = new FormData();
  for (const [name, fallback] of Object.entries(defaults)) {
    const part = name in parts ? parts[name] : fallback;
    if (part === null) continue;
    if (typeof part === "string") form.append(name, part);
    else form.append(name, part[0], part[1]);
  }
  // Serialized here so that the request carries the Content-Length a real one does.
  const encoded = new Response(form);
  const body = await encoded.arrayBuffer();
  const init = {
    method,
    headers: {
      "content-type": encoded.headers.get("content-type"),
      "content-length": String(length ?? body.byteLength),
      "x-moonlight-app": "1.0 (7)",
      "cf-connecting-ip": "203.0.113.9",
      ...headers,
    },
  };
  if (method !== "GET" && method !== "HEAD") init.body = body;
  return new Request(`https://relay.example${path}`, init);
}

const json = (status, value) => new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });

/**
 * A fake of the GitHub API: blobs, trees, commits, main, the Contents API's first commit and
 * issues. `options`: `empty` (no commit yet: blobs answer 409 until the README is put),
 * `noMain` (commits, but no main), `race` (the first update of main loses to another writer),
 * `raceAlways`, `fail` (a route that answers 500: "POST /issues").
 */
function fakeGitHub(options = {}) {
  const calls = [];
  const blobs = new Map();
  const state = { main: options.empty || options.noMain ? null : "commit-0", empty: Boolean(options.empty), races: 0, issues: [], commits: [] };
  const trees = new Map([["tree-0", []]]);
  let counter = 0;
  const next = (kind) => `${kind}-${++counter}`;

  async function handler(url, init = {}) {
    const method = init.method ?? "GET";
    const path = new URL(url).pathname;
    assert.ok(path.startsWith(`/repos/${REPO}/`), `unexpected API path ${path}`);
    const route = path.slice(`/repos/${REPO}`.length);
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    const headers = Object.fromEntries(new Headers(init.headers));
    calls.push({ method, route, body, headers });
    if (options.fail === `${method} ${route}`) return json(500, { message: "boom" });
    assert.equal(headers.authorization, `Bearer ${TOKEN}`);

    if (method === "POST" && route === "/git/blobs") {
      if (state.empty) return json(409, { message: "Git Repository is empty." });
      const sha = next("blob");
      blobs.set(sha, body);
      return json(201, { sha });
    }
    if (method === "PUT" && route === "/contents/README.md") {
      state.empty = false;
      state.main = next("commit");
      state.commits.push({ sha: state.main, tree: "tree-0", parents: [] });
      return json(201, { commit: { sha: state.main } });
    }
    if (method === "GET" && route === "/git/ref/heads/main") {
      if (state.empty) return json(409, { message: "Git Repository is empty." });
      return state.main ? json(200, { object: { sha: state.main, type: "commit" } }) : json(404, { message: "Not Found" });
    }
    const commitMatch = route.match(/^\/git\/commits\/(.+)$/);
    if (method === "GET" && commitMatch) return json(200, { sha: commitMatch[1], tree: { sha: "tree-0" } });
    if (method === "POST" && route === "/git/trees") {
      const sha = next("tree");
      trees.set(sha, body.tree);
      return json(201, { sha });
    }
    if (method === "POST" && route === "/git/commits") {
      const sha = next("commit");
      state.commits.push({ sha, ...body });
      return json(201, { sha });
    }
    if (method === "PATCH" && route === "/git/refs/heads/main") {
      if (options.raceAlways || (options.race && state.races === 0)) {
        state.races += 1;
        state.main = next("commit"); // someone else's report
        return json(422, { message: "Update is not a fast forward" });
      }
      state.main = body.sha;
      return json(200, { object: { sha: body.sha } });
    }
    if (method === "POST" && route === "/git/refs") {
      if (options.race && state.races === 0) {
        state.races += 1;
        state.main = next("commit");
        return json(422, { message: "Reference already exists" });
      }
      assert.equal(body.ref, "refs/heads/main");
      state.main = body.sha;
      return json(201, { ref: body.ref });
    }
    if (method === "POST" && route === "/issues") {
      state.issues.push(body);
      return json(201, { number: state.issues.length, html_url: "https://github.com/secret/issue/1" });
    }
    return json(404, { message: `Unmocked ${method} ${route}` });
  }
  return { handler, calls, state, blobs, trees };
}

let realFetch;
let realError;
let errors;
beforeEach(() => {
  realFetch = globalThis.fetch;
  realError = console.error;
  errors = [];
  console.error = (...args) => {
    const line = args.join(" ");
    // Node 18 warns once that File (what a form's file parts are) is experimental.
    if (/ExperimentalWarning|--trace-warnings/.test(line)) realError(...args);
    else errors.push(line);
  };
  // Nothing may reach the network unless a test installed its fake.
  globalThis.fetch = async (url) => {
    throw new Error(`unexpected fetch of ${url}`);
  };
});
afterEach(() => {
  globalThis.fetch = realFetch;
  console.error = realError;
});

const routes = (fake) => fake.calls.map((call) => `${call.method} ${call.route}`);

async function answers(request, env = ENV) {
  const response = await handle(request, env, DEPS);
  return { status: response.status, text: await response.text(), headers: response.headers };
}

// MARK: Success

test("files the report in one commit and opens an issue", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());

  assert.equal(response.status, 201);
  assert.equal(response.text, '{"ok":true}');
  assert.equal(response.headers.get("content-type"), "application/json");
  assert.deepEqual(routes(fake), [
    "POST /git/blobs",
    "POST /git/blobs",
    "POST /git/blobs",
    "GET /git/ref/heads/main",
    "GET /git/commits/commit-0",
    "POST /git/trees",
    "POST /git/commits",
    "PATCH /git/refs/heads/main",
    "POST /issues",
  ]);

  const [report, picture, bundle] = fake.calls.slice(0, 3).map((call) => call.body);
  assert.deepEqual(report, { content: REPORT, encoding: "utf-8" });
  assert.deepEqual(picture, { encoding: "base64", content: Buffer.from(PNG).toString("base64") });
  assert.deepEqual(bundle, { encoding: "base64", content: Buffer.from(ZIP).toString("base64") });

  const tree = fake.calls[5].body;
  assert.equal(tree.base_tree, "tree-0");
  assert.deepEqual(
    tree.tree.map((entry) => [entry.path, entry.mode, entry.type]),
    [
      [`${FOLDER}/feedback.md`, "100644", "blob"],
      [`${FOLDER}/${PICTURE_NAME}`, "100644", "blob"],
      [`${FOLDER}/${BUNDLE_NAME}`, "100644", "blob"],
    ],
  );
  assert.deepEqual(tree.tree.map((entry) => entry.sha), ["blob-1", "blob-2", "blob-3"]);

  const commit = fake.calls[6].body;
  assert.deepEqual(commit.parents, ["commit-0"]);
  assert.equal(commit.tree, "tree-4");
  assert.match(commit.message, /^Feedback 2026-10-16\/090807-a1b2c3\n\nPaint by Moonlight 1\.0 \(7\)$/);
  assert.deepEqual(fake.calls[7].body, { sha: "commit-5", force: false });
  assert.equal(fake.state.main, "commit-5");

  const [issue] = fake.state.issues;
  assert.equal(fake.state.issues.length, 1);
  assert.equal(issue.title, "Red Fox: feedback (1.0 (7))");
  assert.ok(issue.body.startsWith(REPORT), "the report comes first");
  const blobUrl = `https://github.com/${REPO}/blob/main/${FOLDER}/Red%20Fox%20Feedback%202026-10-05%2014.32.png?raw=1`;
  assert.ok(issue.body.includes(`![The painting with its marks](${blobUrl})`), issue.body);
  assert.ok(issue.body.includes(`](https://github.com/${REPO}/tree/main/${FOLDER})`), issue.body);
  assert.deepEqual(errors, []);
});

test("sends the token to GitHub only, and the same Git Data headers each time", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  await answers(await feedback());
  assert.ok(fake.calls.length > 0);
  for (const call of fake.calls) {
    assert.equal(call.headers.accept, "application/vnd.github+json");
    assert.equal(call.headers["user-agent"], "moonlight-feedback-relay");
  }
});

test("an empty repository is started with a README, then the report goes in as the next commit", async () => {
  const fake = fakeGitHub({ empty: true });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());

  assert.equal(response.status, 201);
  assert.deepEqual(routes(fake), [
    "POST /git/blobs", // 409: no commit yet
    "PUT /contents/README.md",
    "POST /git/blobs",
    "POST /git/blobs",
    "POST /git/blobs",
    "GET /git/ref/heads/main",
    "GET /git/commits/commit-1",
    "POST /git/trees",
    "POST /git/commits",
    "PATCH /git/refs/heads/main",
    "POST /issues",
  ]);
  const readme = fake.calls[1].body;
  assert.equal(Buffer.from(readme.content, "base64").toString().split("\n")[0], "# Paint by Moonlight feedback");
  assert.equal(fake.calls[6].route, "/git/commits/commit-1");
  assert.equal(fake.state.issues.length, 1);
  assert.deepEqual(errors, []);
});

test("a repository with commits but no main gets its first commit as main", async () => {
  const fake = fakeGitHub({ noMain: true });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());

  assert.equal(response.status, 201);
  assert.deepEqual(routes(fake), [
    "POST /git/blobs",
    "POST /git/blobs",
    "POST /git/blobs",
    "GET /git/ref/heads/main", // 404
    "POST /git/trees",
    "POST /git/commits",
    "POST /git/refs",
    "POST /issues",
  ]);
  assert.equal("base_tree" in fake.calls[4].body, false);
  assert.deepEqual(fake.calls[5].body.parents, []);
  assert.deepEqual(fake.calls[6].body, { ref: "refs/heads/main", sha: "commit-5" });
  assert.equal(fake.state.issues.length, 1);
});

test("an empty repository and a lost race together still end with the report on main", async () => {
  const fake = fakeGitHub({ empty: true, race: true });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());
  assert.equal(response.status, 201);
  assert.equal(fake.state.issues.length, 1);
});

// MARK: The ref race

test("retries once when the update of main loses a race, on top of the new main", async () => {
  const fake = fakeGitHub({ race: true });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());

  assert.equal(response.status, 201);
  assert.deepEqual(routes(fake).slice(3), [
    "GET /git/ref/heads/main",
    "GET /git/commits/commit-0",
    "POST /git/trees",
    "POST /git/commits",
    "PATCH /git/refs/heads/main", // 422
    "GET /git/ref/heads/main",
    "GET /git/commits/commit-6",
    "POST /git/trees",
    "POST /git/commits",
    "PATCH /git/refs/heads/main",
    "POST /issues",
  ]);
  // The second commit is on top of the other writer's.
  assert.deepEqual(fake.calls[11].body.parents, ["commit-6"]);
  assert.equal(fake.state.main, "commit-8");
  // The blobs were made once.
  assert.equal(routes(fake).filter((route) => route === "POST /git/blobs").length, 3);
  assert.equal(fake.state.issues.length, 1);
});

test("gives up when main is lost twice, without opening an issue", async () => {
  const fake = fakeGitHub({ raceAlways: true });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());

  assert.equal(response.status, 502);
  assert.equal(response.text, "");
  assert.equal(routes(fake).filter((route) => route === "PATCH /git/refs/heads/main").length, 2);
  assert.equal(fake.state.issues.length, 0);
  assert.equal(errors.length, 1);
});

// MARK: GitHub failures

test("a refused issue is a 502 that tells the app nothing, and the log has no token", async () => {
  const fake = fakeGitHub({ fail: "POST /issues" });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());

  assert.equal(response.status, 502);
  assert.equal(response.text, "");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /POST \/issues answered 500/);
  assert.ok(!errors[0].includes(TOKEN));
});

test("a refused blob stops before any commit", async () => {
  const fake = fakeGitHub({ fail: "POST /git/blobs" });
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback());
  assert.equal(response.status, 502);
  assert.deepEqual(routes(fake), ["POST /git/blobs"]);
});

test("the log never carries the token, even when an error repeats it", async () => {
  globalThis.fetch = async () => {
    throw new Error(`network down while sending ${TOKEN}`);
  };
  const response = await answers(await feedback());
  assert.equal(response.status, 502);
  assert.ok(errors.length > 0);
  assert.ok(errors.every((line) => !line.includes(TOKEN)));
  assert.match(errors[0], /\[token\]/);
});

test("answers nothing about GitHub on success or failure", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const ok = await answers(await feedback());
  for (const secret of [TOKEN, "github.com", "issue", REPO]) assert.ok(!ok.text.includes(secret));
  assert.equal(ok.text, '{"ok":true}');
});

// MARK: Rejections

/** Every rejection is a bare status and reaches neither GitHub nor the log's token. */
async function rejected(request, status, env = ENV) {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const response = await answers(request, env);
  assert.equal(response.status, status);
  assert.equal(response.text, "");
  assert.equal(fake.calls.length, 0, `${status} reached GitHub`);
}

test("rejects another path", async () => {
  await rejected(await feedback({ path: "/v1/other" }), 404);
  await rejected(await feedback({ path: "/" }), 404);
  await rejected(await feedback({ path: "/v1/feedback/" }), 404);
});

test("rejects another method", async () => {
  await rejected(await feedback({ method: "GET" }), 405);
  await rejected(await feedback({ method: "PUT" }), 405);
  await rejected(await feedback({ method: "DELETE" }), 405);
});

test("rejects a missing part", async () => {
  for (const part of ["report", "picture", "bundle"]) {
    await rejected(await feedback({ parts: { [part]: null } }), 400);
  }
});

test("rejects an empty report and a missing app header", async () => {
  await rejected(await feedback({ parts: { report: "  \n" } }), 400);
  await rejected(await feedback({ headers: { "x-moonlight-app": "" } }), 400);
  await rejected(await feedback({ headers: { "x-moonlight-app": "éè" } }), 400);
});

test("takes the report as a plain field too", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const response = await answers(await feedback({ parts: { report: REPORT } }));
  assert.equal(response.status, 201);
  // A form field's line breaks travel as CRLF (the multipart encoding's rule); a file part's bytes don't change.
  assert.equal(fake.calls[0].body.content, REPORT.replaceAll("\n", "\r\n"));
});

test("rejects a body over 30 MB before reading it", async () => {
  await rejected(await feedback({ length: 30 * 1024 * 1024 + 1 }), 413);
  await rejected(await feedback({ length: 900 * 1024 * 1024 }), 413);
});

test("rejects a request without a Content-Length", async () => {
  const request = await feedback();
  request.headers.delete("content-length");
  await rejected(request, 411);
});

test("rejects a body that is not multipart", async () => {
  const request = new Request("https://relay.example/v1/feedback", {
    method: "POST",
    headers: { "content-type": "application/json", "content-length": "2", "x-moonlight-app": "1.0 (7)" },
    body: "{}",
  });
  await rejected(request, 415);
});

test("rejects a picture that is not a PNG", async () => {
  const jpeg = Uint8Array.of(0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0);
  await rejected(await feedback({ parts: { picture: [new Blob([jpeg], { type: "image/png" }), "x.png"] } }), 415);
  await rejected(await feedback({ parts: { picture: [new Blob([PNG.slice(0, 4)], { type: "image/png" }), "x.png"] } }), 415);
  await rejected(await feedback({ parts: { picture: [new Blob([], { type: "image/png" }), "x.png"] } }), 415);
});

test("rejects a bundle that is not a zip", async () => {
  await rejected(await feedback({ parts: { bundle: [new Blob([PNG], { type: "application/zip" }), "x.zip"] } }), 415);
  await rejected(await feedback({ parts: { bundle: [new Blob([ZIP.slice(0, 3)], { type: "application/zip" }), "x.zip"] } }), 415);
});

test("rejects a text part where a file belongs", async () => {
  await rejected(await feedback({ parts: { picture: "not a file" } }), 400);
});

test("rejects a request over the rate limit before reading it", async () => {
  const seen = [];
  const env = { ...ENV, RATE_LIMITER: { limit: async ({ key }) => (seen.push(key), { success: false }) } };
  await rejected(await feedback(), 429, env);
  assert.deepEqual(seen, ["203.0.113.9"]);
});

test("a failing rate limiter lets the report through", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const env = {
    ...ENV,
    RATE_LIMITER: {
      limit: async () => {
        throw new Error("limiter down");
      },
    },
  };
  assert.equal((await answers(await feedback(), env)).status, 201);
  assert.equal(errors.length, 1);
});

test("an allowed request is counted under its IP address", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const seen = [];
  const env = { ...ENV, RATE_LIMITER: { limit: async ({ key }) => (seen.push(key), { success: true }) } };
  assert.equal((await answers(await feedback(), env)).status, 201);
  assert.deepEqual(seen, ["203.0.113.9"]);
});

test("is a 500 without a token or a valid repository, and says so only in the log", async () => {
  await rejected(await feedback(), 500, { FEEDBACK_REPO: REPO });
  await rejected(await feedback(), 500, { FEEDBACK_GITHUB_TOKEN: TOKEN });
  await rejected(await feedback(), 500, { ...ENV, FEEDBACK_REPO: "not a repo/../x" });
  assert.equal(errors.length, 3);
  assert.ok(errors.every((line) => !line.includes(TOKEN)));
});

// MARK: Names

test("keeps the bundle's names but nothing that could leave the folder", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const request = await feedback({
    parts: {
      picture: [new Blob([PNG], { type: "image/png" }), "../../.github/Fox (2) #1?.PNG"],
      bundle: [new Blob([ZIP], { type: "application/zip" }), "..\\..\\evil name"],
    },
  });
  assert.equal((await answers(request)).status, 201);
  const paths = fake.calls.find((call) => call.route === "/git/trees").body.tree.map((entry) => entry.path);
  assert.deepEqual(paths, [`${FOLDER}/feedback.md`, `${FOLDER}/Fox (2) _1_.png`, `${FOLDER}/evil name.zip`]);
  // Parentheses would end the Markdown image early, so the URL spells them out.
  assert.ok(fake.state.issues[0].body.includes("/Fox%20%282%29%20_1_.png?raw=1)"), fake.state.issues[0].body);
});

test("keeps non-ASCII names and gives a nameless file a name", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const request = await feedback({
    parts: {
      picture: [new Blob([PNG], { type: "image/png" }), "Café フィードバック.png"],
      bundle: [new Blob([ZIP], { type: "application/zip" }), "..."],
    },
  });
  assert.equal((await answers(request)).status, 201);
  const paths = fake.calls.find((call) => call.route === "/git/trees").body.tree.map((entry) => entry.path);
  assert.deepEqual(paths.slice(1), [`${FOLDER}/Café フィードバック.png`, `${FOLDER}/feedback.zip`]);
});

test("titles the issue 'Feedback' when the report has no first line, and cuts a long report", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const long = `\n\n${"word ".repeat(20000)}`;
  assert.equal((await answers(await feedback({ parts: { report: long } }))).status, 201);
  const [issue] = fake.state.issues;
  assert.equal(issue.title.startsWith("word word"), true);
  assert.ok(issue.body.length < 65536, `${issue.body.length}`);
  assert.ok(issue.body.includes("the whole report is in the folder"));
  // The report itself is filed whole.
  assert.equal(fake.calls[0].body.content.replaceAll("\r\n", "\n"), long);
});

test("cuts names, titles and the issue's report between characters, never inside one", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  // U+20000 (a letter, two UTF-16 units) straddling each cut: the name's 100, the title's 150 and
  // the issue's 60000.
  const astral = "\u{20000}";
  const report = `${"t".repeat(149)}${astral} title\n\n${"r".repeat(59999)}${astral}${"r".repeat(10)}`;
  const request = await feedback({
    parts: { report, picture: [new Blob([PNG], { type: "image/png" }), `${"p".repeat(99)}${astral}.png`] },
  });
  assert.equal((await answers(request)).status, 201);
  const wellFormed = (text) => !/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/.test(text);
  const paths = fake.calls.find((call) => call.route === "/git/trees").body.tree.map((entry) => entry.path);
  assert.equal(paths[1], `${FOLDER}/${"p".repeat(99)}.png`);
  const [issue] = fake.state.issues;
  assert.ok(wellFormed(issue.title) && issue.title.startsWith(`${"t".repeat(149)} (`), issue.title);
  assert.ok(wellFormed(issue.body) && issue.body.includes("the whole report is in the folder"));
});

test("a report that can't be told as an issue is refused before anything is committed", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  // A lone surrogate can't be encoded for the issue's links: nothing reaches the repository.
  const request = await feedback({ parts: { bundle: [new Blob([ZIP], { type: "application/zip" }), "ok.zip"] } });
  const response = await handle(request, ENV, { ...DEPS, randomHex: () => "a1b2\ud800" });
  assert.equal(response.status, 502);
  assert.deepEqual(routes(fake), []);
});

test("titles an unreadable first line as plain Feedback", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  assert.equal((await answers(await feedback({ parts: { report: "#\n\nbody" } }))).status, 201);
  assert.equal(fake.state.issues[0].title, "Feedback (1.0 (7))");
});

test("names the folder by UTC time and a random suffix of six hex digits", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const response = await handle(await feedback(), ENV, { now: new Date("2026-01-02T03:04:05Z") });
  assert.equal(response.status, 201);
  const path = fake.calls.find((call) => call.route === "/git/trees").body.tree[0].path;
  assert.match(path, /^reports\/2026-01-02\/030405-[0-9a-f]{6}\/feedback\.md$/);
});

// MARK: The Worker entry

test("the Worker's fetch answers like handle and never throws", async () => {
  const fake = fakeGitHub();
  globalThis.fetch = fake.handler;
  const response = await worker.fetch(await feedback(), ENV);
  assert.equal(response.status, 201);

  globalThis.fetch = async () => {
    throw new Error("down");
  };
  const failed = await worker.fetch(await feedback(), ENV);
  assert.equal(failed.status, 502);
  assert.equal(await failed.text(), "");
});
