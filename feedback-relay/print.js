// One Big Sheet (SideStore and Debug builds; painting-company row 380): the relay sends a template
// the painter chose to print to Prodigi's print API, which prints it as one full-size sheet and
// mails it. worker.js routes /v1/print/ here; tested by `node --test feedback-relay/print.test.js`.
//
//   POST /v1/print/quotes          {"product": "<id>", "country": "US"}, application/json, at most
//                                  1 KB. 200 {"product", "currency", "price"[, "sandbox": {"cost",
//                                  "cut"}]}: the price the painter pays, shipping included (Prodigi's
//                                  cost, items and standard shipping, with MARKUP and rounded up to a
//                                  whole unit); "sandbox" says, while the relay talks to the sandbox,
//                                  what the order costs and what is kept.
//   POST /v1/print/orders          multipart/form-data, at most 25 MB: `sheet`, the one-page PDF
//                                  (checked by `%PDF-`), and `order`, JSON {"product", "recipient":
//                                  {"name", "email", "line1", "line2"?, "city", "state"?, "zip",
//                                  "country"}}. The sheet is kept for Prodigi to fetch (below), then
//                                  the order placed. 201 {"ok": true, "order": "<Prodigi's id>",
//                                  "sandbox": true|false}.
//   GET  /v1/print/sheets/<id>/<token>.pdf
//                                  the kept sheet, for Prodigi's printer: 404 for anything else.
//
// Failures are a bare status (the log has the detail): 400 a malformed body or an unknown product,
// 404 another path, 405 another method, 411 no Content-Length, 413 too large, 415 not JSON or
// multipart, or a sheet that is no PDF, 429 over the rate limit (PRINT_LIMITER), 500 misconfigured,
// 502 Prodigi refused, 503 live printing, which this relay doesn't do (below).
//
// Only the sandbox. PRODIGI_API must be Prodigi's sandbox (https://api.sandbox.prodigi.com/v4.0),
// which prints nothing and charges nothing: the relay takes no payment yet, so an order against the
// live API would be printed at Paul's cost for anyone who asked. Going live means a payment checked
// here before the order (Apple Pay through Stripe), and Paul's word.
//
// Privacy: the photo never comes here, only the printed sheet (lines, numbers, the key) and the
// address it goes to. The sheet lives in its own Durable Object (PrintSheet, SQLite-backed, named by
// a random id) under a random token, and deletes itself SHEET_DAYS after it was kept, by an alarm;
// the address goes to Prodigi and is kept nowhere here.
//
// Secret PRODIGI_API_KEY (Prodigi's dashboard › Settings › API; the sandbox key). Variables
// PRODIGI_API and MARKUP (wrangler.toml).

const PREFIX = "/v1/print/";
const QUOTES = "/v1/print/quotes";
const ORDERS = "/v1/print/orders";
const SHEETS = "/v1/print/sheets/";
const SANDBOX = "https://api.sandbox.prodigi.com/v4.0";
const MAX_QUOTE = 1024;
const MAX_ORDER = 25 * 1024 * 1024;
const MAX_FIELD = 200;
const CHUNK = 1024 * 1024;
const SHEET_DAYS = 14;
const SHIPPING = "Standard";
const PDF = [0x25, 0x50, 0x44, 0x46, 0x2d];
const HEX = /^[0-9a-f]{32}$/;
const COUNTRY = /^[A-Z]{2}$/;

/**
 * What One Big Sheet offers, by the id the app sends, and the Prodigi SKU that prints it: Enhanced
 * Matte Art Paper, 200 gsm, which takes markers, gouache and a light coat of acrylic. A SKU here is
 * checked against Prodigi's product lookup before it is offered (GLOBAL-FAP-18x24 is named in
 * Prodigi's FAQ).
 */
export const PRODUCTS = {
  "paper-18x24": "GLOBAL-FAP-18x24",
  "paper-24x36": "GLOBAL-FAP-24x36",
};

export function routesPrint(pathname) {
  return pathname.startsWith(PREFIX);
}

export async function handlePrint(request, env, deps = {}) {
  const url = new URL(request.url);
  if (url.pathname.startsWith(SHEETS)) {
    if (request.method !== "GET" && request.method !== "HEAD") return bare(405, { allow: "GET" });
    return sheet(url.pathname.slice(SHEETS.length), env);
  }
  if (url.pathname !== QUOTES && url.pathname !== ORDERS) return bare(404);
  if (request.method !== "POST") return bare(405, { allow: "POST" });
  if (!env.PRODIGI_API_KEY || !env.PRODIGI_API || !env.PRINT_SHEETS) {
    log("PRODIGI_API_KEY, PRODIGI_API or PRINT_SHEETS is missing");
    return bare(500);
  }
  if (env.PRODIGI_API !== SANDBOX) {
    log("PRODIGI_API is not the sandbox: live printing needs a payment checked first");
    return bare(503);
  }
  if (!(await allowed(env.PRINT_LIMITER, request.headers.get("cf-connecting-ip") ?? "unknown"))) return bare(429);
  return url.pathname === QUOTES ? quote(request, env, deps) : order(request, env, deps);
}

// MARK: Quotes

async function quote(request, env, deps) {
  if (!/^application\/json\b/i.test(request.headers.get("content-type") ?? "")) return bare(415);
  const length = request.headers.get("content-length");
  if (length !== null && Number(length) > MAX_QUOTE) return bare(413);
  const text = await readCapped(request, MAX_QUOTE);
  if (text === null) return bare(413);
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return bare(400);
  }
  const sku = PRODUCTS[body?.product];
  if (typeof body?.product !== "string" || !sku || typeof body?.country !== "string" || !COUNTRY.test(body.country)) {
    return bare(400);
  }
  let answer;
  try {
    answer = await prodigi(env, deps, "POST", "/quotes", {
      shippingMethod: SHIPPING,
      destinationCountryCode: body.country,
      items: [{ sku, copies: 1, attributes: {}, assets: [{ printArea: "default" }] }],
    });
  } catch (error) {
    log("Quoting failed", error);
    return bare(502);
  }
  const chosen = (answer.quotes ?? []).find((q) => q.shipmentMethod === SHIPPING) ?? answer.quotes?.[0];
  const total = chosen?.costSummary?.totalCost;
  const cost = Number(total?.amount);
  if (!chosen || !Number.isFinite(cost) || cost <= 0 || typeof total?.currency !== "string") {
    log("Prodigi's quote had no total");
    return bare(502);
  }
  const price = priceFor(cost, env.MARKUP);
  const result = { product: body.product, currency: total.currency, price: money(price) };
  result.sandbox = { cost: money(cost), cut: money(price - cost) };
  return json(200, result);
}

/** What the painter pays for `cost`: the markup laid on, rounded up to a whole unit. */
export function priceFor(cost, markup) {
  const rate = Number(markup);
  const factor = Number.isFinite(rate) && rate >= 0 && rate < 5 ? 1 + rate : 1.4;
  return Math.ceil(cost * factor - 1e-9);
}

function money(value) {
  return (Math.round(value * 100) / 100).toFixed(2);
}

// MARK: Orders

async function order(request, env, deps) {
  const length = request.headers.get("content-length");
  if (length === null || !/^\d+$/.test(length)) return bare(411);
  if (Number(length) > MAX_ORDER) return bare(413);
  if (!/^multipart\/form-data\s*;/i.test(request.headers.get("content-type") ?? "")) return bare(415);
  let form;
  try {
    form = await request.formData();
  } catch {
    return bare(400);
  }
  const file = form.get("sheet");
  const orderText = form.get("order");
  if (!isBlob(file) || file.size === 0 || typeof orderText !== "string" || orderText.length > 4096) return bare(400);
  if (file.size > MAX_ORDER) return bare(413);
  if (!(await startsWith(file, PDF))) return bare(415);
  let body;
  try {
    body = JSON.parse(orderText);
  } catch {
    return bare(400);
  }
  const sku = PRODUCTS[body?.product];
  const recipient = cleanRecipient(body?.recipient);
  if (typeof body?.product !== "string" || !sku || !recipient) return bare(400);

  const id = (deps.randomHex ?? randomHex)(), token = (deps.randomHex ?? randomHex)();
  const kept = await sheetStub(env, id).fetch("https://sheet/keep", {
    method: "POST",
    headers: { "x-token": token, "x-days": String(SHEET_DAYS) },
    body: await file.arrayBuffer(),
  });
  if (!kept.ok) {
    log(`Keeping the sheet failed: HTTP ${kept.status}`);
    return bare(502);
  }
  const origin = new URL(request.url).origin;
  let placed;
  try {
    placed = await prodigi(env, deps, "POST", "/orders", {
      merchantReference: `sheet-${id.slice(0, 12)}`,
      shippingMethod: SHIPPING,
      recipient: {
        name: recipient.name,
        email: recipient.email,
        address: {
          line1: recipient.line1,
          line2: recipient.line2,
          postalOrZipCode: recipient.zip,
          countryCode: recipient.country,
          townOrCity: recipient.city,
          stateOrCounty: recipient.state,
        },
      },
      items: [{
        merchantReference: "sheet",
        sku,
        copies: 1,
        sizing: "fitPrintArea",
        assets: [{ printArea: "default", url: `${origin}${SHEETS}${id}/${token}.pdf` }],
      }],
    });
  } catch (error) {
    log("Placing the order failed", error);
    await sheetStub(env, id).fetch("https://sheet/drop", { method: "POST" }).catch(() => {});
    return bare(502);
  }
  const orderId = placed?.order?.id;
  if (typeof orderId !== "string") {
    log("Prodigi's answer had no order id");
    return bare(502);
  }
  return json(201, { ok: true, order: orderId, sandbox: env.PRODIGI_API === SANDBOX });
}

/** The recipient with every field a trimmed string of sensible length, or null. */
export function cleanRecipient(value) {
  if (!value || typeof value !== "object") return null;
  const field = (name, required) => {
    const raw = value[name];
    if (raw === undefined || raw === null || raw === "") return required ? null : "";
    if (typeof raw !== "string") return null;
    const text = raw.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
    if (text.length > MAX_FIELD || (required && text === "")) return null;
    return text;
  };
  const cleaned = {
    name: field("name", true), email: field("email", true), line1: field("line1", true), line2: field("line2", false),
    city: field("city", true), state: field("state", false), zip: field("zip", true), country: field("country", true),
  };
  if (Object.values(cleaned).some((v) => v === null)) return null;
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleaned.email) || !COUNTRY.test(cleaned.country)) return null;
  return cleaned;
}

// MARK: Sheets

async function sheet(rest, env) {
  const match = /^([0-9a-f]{32})\/([0-9a-f]{32})\.pdf$/.exec(rest);
  if (!match || !env.PRINT_SHEETS) return bare(404);
  const answer = await sheetStub(env, match[1]).fetch("https://sheet/read", { headers: { "x-token": match[2] } });
  if (!answer.ok) return bare(404);
  return new Response(answer.body, {
    status: 200,
    headers: { "content-type": "application/pdf", "cache-control": "private, no-store" },
  });
}

function sheetStub(env, id) {
  return env.PRINT_SHEETS.get(env.PRINT_SHEETS.idFromName(id));
}

/**
 * One kept sheet, a Durable Object named by a random id: the PDF in chunks (a stored value is at
 * most 2 MB), its token, and an alarm that deletes it all.
 *   POST https://sheet/keep   the PDF as the body; x-token, x-days
 *   GET  https://sheet/read   x-token; the PDF, or 404
 *   POST https://sheet/drop   deletes it now (an order that failed)
 */
export class PrintSheet {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/keep" && request.method === "POST") {
      const token = request.headers.get("x-token") ?? "";
      const days = Number(request.headers.get("x-days"));
      if (!HEX.test(token) || !(days > 0)) return bare(400);
      const bytes = new Uint8Array(await request.arrayBuffer());
      const chunks = Math.ceil(bytes.byteLength / CHUNK);
      const entries = { token, chunks };
      for (let i = 0; i < chunks; i++) entries[`chunk-${i}`] = bytes.slice(i * CHUNK, (i + 1) * CHUNK);
      await this.storage.put(entries);
      await this.storage.setAlarm(Date.now() + days * 24 * 3600 * 1000);
      return json(201, { ok: true });
    }
    if (pathname === "/read" && request.method === "GET") {
      const token = await this.storage.get("token");
      if (!token || token !== request.headers.get("x-token")) return bare(404);
      const chunks = (await this.storage.get("chunks")) ?? 0;
      const parts = [];
      for (let i = 0; i < chunks; i++) parts.push(await this.storage.get(`chunk-${i}`));
      return new Response(new Blob(parts), { status: 200, headers: { "content-type": "application/pdf" } });
    }
    if (pathname === "/drop" && request.method === "POST") {
      await this.storage.deleteAll();
      return json(200, { ok: true });
    }
    return bare(404);
  }

  async alarm() {
    await this.storage.deleteAll();
  }
}

// MARK: Prodigi

async function prodigi(env, deps, method, path, body) {
  const fetcher = deps.fetch ?? fetch;
  const response = await fetcher(`${env.PRODIGI_API}${path}`, {
    method,
    headers: { "x-api-key": env.PRODIGI_API_KEY, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`Prodigi ${method} ${path}: HTTP ${response.status} ${text.slice(0, 300)}`);
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Prodigi ${method} ${path}: not JSON`);
  }
}

// MARK: Helpers

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
  return new TextDecoder().decode(await new Blob(chunks).arrayBuffer());
}

async function allowed(limiter, key) {
  if (!limiter) return true;
  try {
    return (await limiter.limit({ key })).success;
  } catch {
    return true;
  }
}

function isBlob(value) {
  return typeof value === "object" && value !== null && typeof value.arrayBuffer === "function" && typeof value.size === "number";
}

async function startsWith(blob, magic) {
  const head = new Uint8Array(await blob.slice(0, magic.length).arrayBuffer());
  return head.length === magic.length && magic.every((byte, i) => head[i] === byte);
}

function randomHex() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function bare(status, headers) {
  return new Response(null, { status, headers });
}

function json(status, value) {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json" } });
}

function log(what, error) {
  const detail = error === undefined ? "" : `: ${error instanceof Error ? error.message : String(error)}`;
  console.error(`${what}${detail}`);
}
