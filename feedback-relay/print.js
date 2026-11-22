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
//                                  "country"}[, "price", "currency", "payment": {"data", "network",
//                                  "transactionId", "instrument"}]}. With STRIPE_SECRET_KEY set the
//                                  order is paid first: the price is quoted again and must be the
//                                  one the painter agreed to (409 if it moved), and the Apple Pay
//                                  payment (PKPaymentToken's paymentData, base64) is charged through
//                                  Stripe (402 declined or missing). Then the sheet is kept for
//                                  Prodigi to fetch (below) and the order placed; a payment whose
//                                  order fails is refunded. 201 {"ok": true, "order": "<Prodigi's
//                                  id>", "sandbox": true|false, "paid": true|false}.
//   GET  /v1/print/sheets/<id>/<token>.pdf
//                                  the kept sheet, for Prodigi's printer: 404 for anything else.
//
// Failures are a bare status (the log has the detail): 400 a malformed body or an unknown product,
// 404 another path, 405 another method, 411 no Content-Length, 413 too large, 415 not JSON or
// multipart, or a sheet that is no PDF, 429 over the rate limit (PRINT_LIMITER), 500 misconfigured,
// 502 Prodigi or Stripe refused, 503 live printing or charging, which this relay doesn't do (below).
//
// Only the sandbox. PRODIGI_API must be Prodigi's sandbox (https://api.sandbox.prodigi.com/v4.0),
// which prints nothing and charges nothing, and STRIPE_SECRET_KEY, when set, Stripe's test mode
// (sk_test_), so no real card is charged for a print that never comes. Going live is Paul's word,
// with both keys live and payment required (no order without STRIPE_SECRET_KEY).
//
// Privacy: the photo never comes here, only the printed sheet (lines, numbers, the key) and the
// address it goes to. The sheet lives in its own Durable Object (PrintSheet, SQLite-backed, named by
// a random id) under a random token, and deletes itself SHEET_DAYS after it was kept, by an alarm;
// the address goes to Prodigi and is kept nowhere here.
//
// The print service is one object (`prodigi` below; PRINT_PROVIDER names another), so it can be
// replaced without touching the rest. Secrets PRODIGI_API_KEY (Prodigi's dashboard › Settings › API; the sandbox key) and, optional,
// STRIPE_SECRET_KEY (Stripe's dashboard › Developers › API keys; the test key). Variables
// PRODIGI_API and MARKUP (wrangler.toml).

import { Buffer } from "node:buffer";

const PREFIX = "/v1/print/";
const QUOTES = "/v1/print/quotes";
const ORDERS = "/v1/print/orders";
const SHEETS = "/v1/print/sheets/";
const SANDBOX = "https://api.sandbox.prodigi.com/v4.0";
const STRIPE = "https://api.stripe.com/v1";
const MAX_QUOTE = 1024;
const MAX_ORDER = 25 * 1024 * 1024;
const MAX_FIELD = 200;
const CHUNK = 1024 * 1024;
const SHEET_DAYS = 14;
const SHIPPING = "Standard";
const PDF = [0x25, 0x50, 0x44, 0x46, 0x2d];
const HEX = /^[0-9a-f]{32}$/;
const COUNTRY = /^[A-Z]{2}$/;

// MARK: The print service

/**
 * A print service is one object (PRINT_PROVIDER picks it, Prodigi by default), so another (Gelato,
 * say) is a second object of the same shape and nothing else here changes:
 *   products              the app's product ids → the service's own product codes
 *   configured(env)       whether its secrets and settings are there
 *   isSandbox(env)        whether it is talking to its test system, which prints nothing
 *   cost(env, deps, code, country)   → {cost, currency}: one sheet sent there, shipping included
 *   place(env, deps, {reference, code, recipient, sheetUrl})   → the service's order id
 */
export const prodigi = {
  name: "Prodigi",
  // Enhanced Matte Art Paper, 200 gsm, which takes markers, gouache and a light coat of acrylic.
  // A code here is checked against Prodigi's product lookup before it is offered
  // (GLOBAL-FAP-18x24 is named in Prodigi's FAQ).
  products: {
    "paper-18x24": "GLOBAL-FAP-18x24",
    "paper-24x36": "GLOBAL-FAP-24x36",
  },

  configured: (env) => Boolean(env.PRODIGI_API_KEY && env.PRODIGI_API),

  isSandbox: (env) => env.PRODIGI_API === SANDBOX,

  async cost(env, deps, code, country) {
    const answer = await prodigiCall(env, deps, "POST", "/quotes", {
      shippingMethod: SHIPPING,
      destinationCountryCode: country,
      items: [{ sku: code, copies: 1, attributes: {}, assets: [{ printArea: "default" }] }],
    });
    const chosen = (answer.quotes ?? []).find((q) => q.shipmentMethod === SHIPPING) ?? answer.quotes?.[0];
    const total = chosen?.costSummary?.totalCost;
    const cost = Number(total?.amount);
    if (!chosen || !Number.isFinite(cost) || cost <= 0 || typeof total?.currency !== "string") {
      throw new Error("Prodigi's quote had no total");
    }
    return { cost, currency: total.currency };
  },

  async place(env, deps, { reference, code, recipient, sheetUrl }) {
    const placed = await prodigiCall(env, deps, "POST", "/orders", {
      merchantReference: reference,
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
        sku: code,
        copies: 1,
        sizing: "fitPrintArea",
        assets: [{ printArea: "default", url: sheetUrl }],
      }],
    });
    const id = placed?.order?.id;
    if (typeof id !== "string") throw Object.assign(new Error("Prodigi's answer had no order id"), { uncertain: true });
    return id;
  },
};

const PROVIDERS = { prodigi };

function providerOf(env) {
  return PROVIDERS[env.PRINT_PROVIDER ?? "prodigi"] ?? null;
}

/** The products the default service offers (the tests'). */
export const PRODUCTS = prodigi.products;

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
  const provider = providerOf(env);
  if (!provider || !provider.configured(env) || !env.PRINT_SHEETS) {
    log("The print service, its secrets or PRINT_SHEETS are missing");
    return bare(500);
  }
  if (!provider.isSandbox(env)) {
    log(`${provider.name} is not its sandbox: live printing waits for Paul's word`);
    return bare(503);
  }
  if (!(await allowed(env.PRINT_LIMITER, request.headers.get("cf-connecting-ip") ?? "unknown"))) return bare(429);
  return url.pathname === QUOTES ? quote(request, env, deps, provider) : order(request, env, deps, provider);
}

// MARK: Quotes

async function quote(request, env, deps, provider) {
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
  const code = provider.products[body?.product];
  if (typeof body?.product !== "string" || !code || typeof body?.country !== "string" || !COUNTRY.test(body.country)) {
    return bare(400);
  }
  let priced;
  try {
    priced = await priceOf(env, deps, provider, code, body.country);
  } catch (error) {
    log("Quoting failed", error);
    return bare(502);
  }
  return json(200, {
    product: body.product, currency: priced.currency, price: money(priced.price),
    sandbox: { cost: money(priced.cost), cut: money(priced.price - priced.cost) },
  });
}

/** The service's cost of one sheet sent to `country`, shipping included, and the painter's price. */
async function priceOf(env, deps, provider, code, country) {
  const { cost, currency } = await provider.cost(env, deps, code, country);
  return { cost, currency, price: priceFor(cost, env.MARKUP) };
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

async function order(request, env, deps, provider) {
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
  const code = provider.products[body?.product];
  const recipient = cleanRecipient(body?.recipient);
  if (typeof body?.product !== "string" || !code || !recipient) return bare(400);

  const id = (deps.randomHex ?? randomHex)(), token = (deps.randomHex ?? randomHex)();
  let charge = null;
  if (env.STRIPE_SECRET_KEY) {
    // Prodigi's sandbox prints nothing: a live card is never charged for it.
    if (!env.STRIPE_SECRET_KEY.startsWith("sk_test_")) {
      log(`STRIPE_SECRET_KEY is live while ${provider.name} is its sandbox`);
      return bare(503);
    }
    const payment = cleanPayment(body?.payment);
    if (!payment) return bare(402);
    let priced;
    try {
      priced = await priceOf(env, deps, provider, code, recipient.country);
    } catch (error) {
      log("Pricing the order failed", error);
      return bare(502);
    }
    // The painter agreed to the price on screen: a price that moved since is asked again.
    if (money(priced.price) !== body.price || priced.currency !== body.currency) return bare(409);
    try {
      charge = await chargeApplePay(env, deps, payment, priced, id);
    } catch (error) {
      log("Charging the order failed", error);
      return bare(error?.declined ? 402 : 502);
    }
  }
  const kept = await sheetStub(env, id).fetch("https://sheet/keep", {
    method: "POST",
    headers: { "x-token": token, "x-days": String(SHEET_DAYS) },
    body: await file.arrayBuffer(),
  });
  if (!kept.ok) {
    log(`Keeping the sheet failed: HTTP ${kept.status}`);
    await refund(env, deps, charge);
    return bare(502);
  }
  const origin = new URL(request.url).origin;
  let orderId;
  try {
    orderId = await provider.place(env, deps, {
      reference: `sheet-${id.slice(0, 12)}`, code, recipient, sheetUrl: `${origin}${SHEETS}${id}/${token}.pdf`,
    });
  } catch (error) {
    if (error?.uncertain) {
      // The service may have taken it: the sheet and the payment stay, the log has them for a look by hand.
      log(`${provider.name} may hold sheet ${id} (payment ${charge ?? "none"})`, error);
      return bare(502);
    }
    log("Placing the order failed", error);
    await sheetStub(env, id).fetch("https://sheet/drop", { method: "POST" }).catch(() => {});
    await refund(env, deps, charge);
    return bare(502);
  }
  return json(201, { ok: true, order: orderId, sandbox: provider.isSandbox(env), paid: charge !== null });
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

// MARK: Payment

/**
 * The Apple Pay payment the app hands on: PKPaymentToken's paymentData (base64), its network,
 * transaction id and the card's display name, or null.
 */
export function cleanPayment(value) {
  if (!value || typeof value !== "object") return null;
  const { data, network, transactionId, instrument } = value;
  if (typeof data !== "string" || data.length === 0 || data.length > 16384 || !/^[A-Za-z0-9+/=]+$/.test(data)) return null;
  for (const field of [network, transactionId, instrument]) {
    if (field !== undefined && (typeof field !== "string" || field.length > 200)) return null;
  }
  return { data, network: network ?? "", transactionId: transactionId ?? "", instrument: instrument ?? "" };
}

// Currencies Stripe counts in whole units.
const ZERO_DECIMAL = new Set(["JPY", "KRW"]);

/** Stripe's amount for `price` in `currency`: cents, or whole units where it counts so. */
export function minorUnits(price, currency) {
  return ZERO_DECIMAL.has(currency.toUpperCase()) ? Math.round(price) : Math.round(price * 100);
}

/**
 * Charges the price through Stripe: the Apple Pay token made a Stripe token (as Stripe's iOS SDK
 * does, `pk_token`), then a PaymentIntent confirmed at once. Returns its id once it succeeded;
 * a declined card throws with `declined`.
 */
async function chargeApplePay(env, deps, payment, priced, id) {
  const pkToken = Buffer.from(payment.data, "base64").toString("utf8");
  const token = await stripe(env, deps, "/tokens", {
    pk_token: pkToken,
    pk_token_instrument_name: payment.instrument,
    pk_token_payment_network: payment.network,
    pk_token_transaction_id: payment.transactionId,
  });
  if (typeof token?.id !== "string") throw new Error("Stripe made no token");
  const intent = await stripe(env, deps, "/payment_intents", {
    amount: String(minorUnits(priced.price, priced.currency)),
    currency: priced.currency.toLowerCase(),
    confirm: "true",
    "payment_method_types[]": "card",
    "payment_method_data[type]": "card",
    "payment_method_data[card][token]": token.id,
    description: "One Big Sheet",
    "metadata[sheet]": id,
  });
  if (intent?.status !== "succeeded" || typeof intent?.id !== "string") {
    const error = new Error(`Stripe's payment is ${intent?.status ?? "missing"}`);
    error.declined = true;
    throw error;
  }
  return intent.id;
}

/** Gives a payment back (an order that couldn't be placed after it); logs what it can't. */
async function refund(env, deps, charge) {
  if (!charge) return;
  try {
    await stripe(env, deps, "/refunds", { payment_intent: charge });
  } catch (error) {
    log(`Refunding ${charge} failed`, error);
  }
}

async function stripe(env, deps, path, fields) {
  const fetcher = deps.fetch ?? fetch;
  const response = await fetcher(`${STRIPE}${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.STRIPE_SECRET_KEY}`, "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  const text = await response.text();
  let answer;
  try {
    answer = JSON.parse(text);
  } catch {
    throw new Error(`Stripe ${path}: HTTP ${response.status}, not JSON`);
  }
  if (!response.ok) {
    const error = new Error(`Stripe ${path}: HTTP ${response.status} ${answer?.error?.code ?? ""}`);
    error.declined = answer?.error?.type === "card_error";
    throw error;
  }
  return answer;
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

// MARK: Prodigi's API

async function prodigiCall(env, deps, method, path, body) {
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
