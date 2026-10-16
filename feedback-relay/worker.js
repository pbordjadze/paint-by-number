// The relay behind Give Feedback in Paint by Moonlight: a Cloudflare Worker that takes a report
// from the app and files it in a private GitHub repository, so it reaches the developers without
// a mail account, an address or a share sheet. Deployed by .github/workflows/feedback-relay.yml;
// tested by `node --test feedback-relay/worker.test.js` (GitHub mocked; CI's `core` job runs it).
//
//   POST /v1/feedback   multipart/form-data, at most 30 MB, with
//     report   the bundle's feedback.md, as text
//     picture  the painting with its marks (PNG, checked by its magic bytes)
//     bundle   the zip FeedbackPackage writes (checked by `PK\x03\x04`)
//   and the header X-Moonlight-App, the app's version and build.
//
// It commits the three files to refs/heads/main of the repository named by the variable
// FEEDBACK_REPO, in one commit made with the Git Data API (blobs, tree, commit, ref), under
//   reports/<yyyy-mm-dd>/<HHMMSS>-<6 hex>/   (UTC; the picture and the bundle keep their names,
//                                             the report is feedback.md)
// and opens an issue there: the report's first line and the app version as its title, the report,
// the picture and a link to the folder as its body. A raced ref update is retried once. An empty
// repository (no commit, so GitHub refuses blobs) is started with a README through the Contents
// API; a repository without a main branch gets its first commit as main.
//
// Answers: 201 {"ok":true} and nothing else on success. Failures are a bare status, never a
// detail (the log, `wrangler tail`, has those, never the token): 400 a missing or empty part or
// header, 404 another path, 405 another method, 411 no Content-Length, 413 over 30 MB, 415 not
// multipart, or a picture that is no PNG, or a bundle that is no zip, 429 over the rate limit,
// 500 the relay is misconfigured, 502 GitHub refused.
//
// Secret FEEDBACK_GITHUB_TOKEN: a fine-grained token with Contents and Issues read and write on
// that repository only. Variable FEEDBACK_REPO and the RATE_LIMITER binding: wrangler.toml.
// Rate limiting is a flood brake per IP address (the binding's periods are 10 or 60 seconds, so
// a limit per hour can't be made with it), applied before the body is read; it is per Cloudflare
// location and approximate by design.
//
// Memory: a request is parsed once and its files are read and encoded one at a time (the Workers
// limit is 128 MB). Base64 comes from node:buffer (nodejs_compat), which is native: Workers' free
// plan allows 10 ms of CPU per request.

import { Buffer } from "node:buffer";

const PATH = "/v1/feedback";
const BRANCH = "main";
const MAX_BODY = 30 * 1024 * 1024;
const MAX_REPORT = 1024 * 1024;
// GitHub refuses issue bodies over 65536 characters.
const MAX_ISSUE_REPORT = 60000;
const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const ZIP = [0x50, 0x4b, 0x03, 0x04];
const README = "# Paint by Moonlight feedback\n\nReports sent from the app, one folder each under reports/.\n";

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      log(env, "Unexpected failure", error);
      return reject(500);
    }
  },
};

/**
 * Answers one request. `deps.now` and `deps.randomHex` exist for the tests.
 */
export async function handle(request, env, deps = {}) {
  const url = new URL(request.url);
  if (url.pathname !== PATH) return reject(404);
  if (request.method !== "POST") return reject(405, { allow: "POST" });
  if (!configured(env)) {
    log(env, "FEEDBACK_REPO or FEEDBACK_GITHUB_TOKEN is missing or malformed");
    return reject(500);
  }
  if (!(await withinRate(request, env))) return reject(429);

  const length = request.headers.get("content-length");
  if (length === null || !/^\d+$/.test(length)) return reject(411);
  if (Number(length) > MAX_BODY) return reject(413);
  if (!/^multipart\/form-data\s*;/i.test(request.headers.get("content-type") ?? "")) return reject(415);
  const app = cleanApp(request.headers.get("x-moonlight-app"));
  if (!app) return reject(400);

  let form;
  try {
    form = await request.formData();
  } catch {
    return reject(400);
  }
  const report = form.get("report");
  const picture = form.get("picture");
  const bundle = form.get("bundle");
  if (!isBlob(picture) || !isBlob(bundle) || report === null || (typeof report !== "string" && !isBlob(report))) {
    return reject(400);
  }
  if (typeof report !== "string" && report.size > MAX_REPORT) return reject(413);
  if (picture.size + bundle.size > MAX_BODY) return reject(413);
  const reportText = typeof report === "string" ? report : await report.text();
  if (reportText.trim() === "") return reject(400);
  if (reportText.length > MAX_REPORT) return reject(413);
  if (!(await startsWith(picture, PNG)) || !(await startsWith(bundle, ZIP))) return reject(415);

  const when = (deps.now ?? new Date()).toISOString();
  const folder = `reports/${when.slice(0, 10)}/${when.slice(11, 19).replaceAll(":", "")}-${(deps.randomHex ?? randomHex)()}`;
  const pictureName = safeName(picture.name, ".png", "painting");
  const bundleName = safeName(bundle.name, ".zip", "feedback");
  const files = [
    { path: `${folder}/feedback.md`, text: reportText },
    { path: `${folder}/${pictureName}`, blob: picture },
    { path: `${folder}/${bundleName}`, blob: bundle },
  ];

  try {
    const gh = github(env);
    await commitFiles(gh, files, `Feedback ${folder.slice("reports/".length)}\n\nPaint by Moonlight ${app}`);
    gh.expect(
      await gh.call("POST", "/issues", {
        title: issueTitle(reportText, app),
        body: issueBody(env.FEEDBACK_REPO, reportText, folder, pictureName),
      }),
    );
  } catch (error) {
    log(env, "Filing the report failed", error);
    return reject(502);
  }
  return new Response('{"ok":true}', { status: 201, headers: { "content-type": "application/json" } });
}

// MARK: Request checks

function reject(status, headers) {
  return new Response(null, { status, headers });
}

function configured(env) {
  return (
    typeof env.FEEDBACK_GITHUB_TOKEN === "string" &&
    env.FEEDBACK_GITHUB_TOKEN !== "" &&
    /^[\w.-]+\/[\w.-]+$/.test(env.FEEDBACK_REPO ?? "")
  );
}

async function withinRate(request, env) {
  if (!env.RATE_LIMITER) return true;
  try {
    const { success } = await env.RATE_LIMITER.limit({ key: request.headers.get("cf-connecting-ip") ?? "unknown" });
    return success;
  } catch (error) {
    // A broken limiter must not turn every report away.
    log(env, "The rate limiter failed", error);
    return true;
  }
}

function isBlob(value) {
  return value !== null && typeof value === "object" && typeof value.arrayBuffer === "function" && typeof value.slice === "function";
}

async function startsWith(blob, magic) {
  const head = new Uint8Array(await blob.slice(0, magic.length).arrayBuffer());
  return head.length === magic.length && magic.every((byte, index) => head[index] === byte);
}

function cleanApp(value) {
  return (value ?? "").replace(/[^\x20-\x7e]/g, "").trim().slice(0, 40);
}

// MARK: Names and text

function randomHex() {
  return Array.from(crypto.getRandomValues(new Uint8Array(3)), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

/** A file name from the app, made safe for a path in the repository: it keeps its letters, digits, spaces and a few marks. */
function safeName(name, extension, fallback) {
  let base = String(name ?? "").split(/[\\/]/).pop().normalize("NFC");
  base = base.replace(/[^\p{L}\p{N} ._()-]/gu, "_").replace(/^[.\s]+/, "");
  if (base.toLowerCase().endsWith(extension)) base = base.slice(0, -extension.length);
  base = base.slice(0, 100).replace(/[.\s]+$/, "");
  return (base || fallback) + extension;
}

/** A path for a URL: every segment encoded, and the characters Markdown reads as syntax. */
function encodePath(path) {
  return path
    .split("/")
    .map((segment) => encodeURIComponent(segment).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`))
    .join("/");
}

function issueTitle(report, app) {
  const first = report.split(/\r?\n/).find((line) => line.trim() !== "") ?? "";
  const heading = first.replace(/[\x00-\x1f]/g, " ").replace(/^#+\s*/, "").trim().slice(0, 150);
  return `${heading || "Feedback"} (${app})`;
}

function issueBody(repo, report, folder, pictureName) {
  const picture = `https://github.com/${repo}/blob/${BRANCH}/${encodePath(`${folder}/${pictureName}`)}?raw=1`;
  const files = `https://github.com/${repo}/tree/${BRANCH}/${encodePath(folder)}`;
  const text =
    report.length > MAX_ISSUE_REPORT ? `${report.slice(0, MAX_ISSUE_REPORT)}\n\n(Cut here: the whole report is in the folder.)` : report;
  return `${text}\n\n![The painting with its marks](${picture})\n\n[All the files of this report](${files})\n`;
}

// MARK: GitHub

class GitHubError extends Error {}

function github(env) {
  const repo = env.FEEDBACK_REPO;
  return {
    /** One call to the repository's API: `{ status, ok, json }` (json is null when the body isn't). */
    async call(method, path, body) {
      const response = await fetch(`https://api.github.com/repos/${repo}${path}`, {
        method,
        headers: {
          authorization: `Bearer ${env.FEEDBACK_GITHUB_TOKEN}`,
          accept: "application/vnd.github+json",
          "x-github-api-version": "2022-11-28",
          "user-agent": "moonlight-feedback-relay",
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        body: body === undefined || typeof body === "string" ? body : JSON.stringify(body),
      });
      let json = null;
      try {
        json = await response.json();
      } catch {
        // An empty or non-JSON body.
      }
      return { method, path, status: response.status, ok: response.ok, json };
    },
    /** `result`, or a GitHubError saying what was refused. */
    expect(result) {
      if (!result.ok) {
        throw new GitHubError(`${result.method} ${result.path} answered ${result.status}: ${String(result.json?.message ?? "").slice(0, 200)}`);
      }
      return result;
    },
  };
}

/** One commit with `files` on top of main (or the first commit of main), with the ref update retried once. */
async function commitFiles(gh, files, message) {
  let started = false;
  const blobs = [];
  for (const file of files) {
    const body = await blobBody(file);
    let result = await gh.call("POST", "/git/blobs", body);
    if (result.status === 409 && !started) {
      // An empty repository has no objects yet, and GitHub refuses blobs there until it has a commit.
      started = true;
      await start(gh);
      result = await gh.call("POST", "/git/blobs", body);
    }
    blobs.push({ path: file.path, mode: "100644", type: "blob", sha: gh.expect(result).json.sha });
  }

  for (let attempt = 0; ; attempt += 1) {
    const head = await readHead(gh);
    const tree = gh.expect(await gh.call("POST", "/git/trees", { base_tree: head?.tree, tree: blobs })).json.sha;
    const commit = gh.expect(await gh.call("POST", "/git/commits", { message, tree, parents: head ? [head.commit] : [] })).json.sha;
    const update = head
      ? await gh.call("PATCH", `/git/refs/heads/${BRANCH}`, { sha: commit, force: false })
      : await gh.call("POST", "/git/refs", { ref: `refs/heads/${BRANCH}`, sha: commit });
    if (update.ok) return;
    // Another report moved main (or made it) between reading it and updating it.
    if (attempt === 0 && (update.status === 422 || update.status === 409)) continue;
    gh.expect(update);
  }
}

/** The JSON of a blob: text as UTF-8, a file as base64 (read now, and let go of after this). */
async function blobBody(file) {
  if (file.text !== undefined) return JSON.stringify({ content: file.text, encoding: "utf-8" });
  // Base64 has no characters JSON would escape, so the (large) string is joined, never scanned.
  return `{"encoding":"base64","content":"${Buffer.from(await file.blob.arrayBuffer()).toString("base64")}"}`;
}

/** The commit and tree main points at, or null when there is no main (yet). */
async function readHead(gh) {
  const ref = await gh.call("GET", `/git/ref/heads/${BRANCH}`);
  if (ref.status === 404 || ref.status === 409) return null;
  const commit = gh.expect(ref).json.object.sha;
  return { commit, tree: gh.expect(await gh.call("GET", `/git/commits/${commit}`)).json.tree.sha };
}

/** Makes the first commit of an empty repository, which the Contents API can and the Git Data API can't. */
async function start(gh) {
  const result = await gh.call("PUT", "/contents/README.md", {
    message: "Start the feedback repository",
    content: Buffer.from(README).toString("base64"),
  });
  // 422: the file is there already, so the repository wasn't empty after all.
  if (result.status !== 422) gh.expect(result);
}

function log(env, what, error) {
  let detail = error === undefined ? "" : `: ${error instanceof Error ? error.message : String(error)}`;
  if (env.FEEDBACK_GITHUB_TOKEN) detail = detail.replaceAll(env.FEEDBACK_GITHUB_TOKEN, "[token]");
  console.error(`${what}${detail}`);
}
