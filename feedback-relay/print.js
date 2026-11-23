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
//                                  (checked by `%PDF-`), and `order`, JSON (a field or a file part,
//                                  at most 32 KB) {"key", "product", "recipient": {"name", "email",
//                                  "line1", "line2"?, "city", "state"?, "zip", "country"}[, "price",
//                                  "currency", "payment": {"data", "network", "transactionId",
//                                  "instrument"}]}. `key` (32 hex digits) is the app's for this
//                                  order, the same on every try of it: the sheet and where the order
//                                  stands are kept under it, so an order is charged and placed once.
//                                  With STRIPE_SECRET_KEY set the order is paid first: the price is
//                                  quoted again and must be the one the painter agreed to (409 if it
//                                  moved), and the Apple Pay payment (PKPaymentToken's paymentData,
//                                  base64) is charged through Stripe (402 declined or missing). Then
//                                  the order is placed with the sheet's URL (below); a payment whose
//                                  order surely failed is refunded. 201 {"ok": true, "order":
//                                  "<Prodigi's id>", "sandbox": true|false, "paid": true|false}, also
//                                  for a try of an order placed already; 202 {"ok": false, "pending":
//                                  true} for one still under way, or left uncertain (Stripe or
//                                  Prodigi gave no clear answer: the log names it for a look by hand).
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
// the order's random key) under a random token, and deletes itself SHEET_DAYS after it was kept, by an alarm;
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
// An Apple Pay token (a PKCS#7 signature with its certificates, base64) is several KB.
const MAX_ORDER_JSON = 32 * 1024;
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
 *   place(env, deps, {reference, key, code, recipient, sheetUrl})   → the service's order id; the
 *                         same key placed again must not make a second order, and an error that
 *                         leaves it unknown whether one was made carries `uncertain`
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

  async place(env, deps, { reference, key, code, recipient, sheetUrl }) {
    // An order made again under the same idempotency key is answered with the one already made.
    const placed = await prodigiCall(env, deps, "POST", "/orders", {
      idempotencyKey: key,
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
  const orderText = await partText(form.get("order"), MAX_ORDER_JSON);
  if (!isBlob(file) || file.size === 0 || orderText === null) return bare(400);
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
  // The app's key for this order, the same on every try of it: an order is charged and placed once.
  const key = body?.key;
  if (typeof body?.product !== "string" || !code || !recipient || typeof key !== "string" || !HEX.test(key)) return bare(400);

  let payment = null;
  if (env.STRIPE_SECRET_KEY) {
    // Prodigi's sandbox prints nothing: a live card is never charged for it.
    if (!env.STRIPE_SECRET_KEY.startsWith("sk_test_")) {
      log(`STRIPE_SECRET_KEY is live while ${provider.name} is its sandbox`);
      return bare(503);
    }
    payment = cleanPayment(body?.payment);
    if (!payment) return bare(402);
  }

  // The order's Durable Object keeps the sheet and where the order stands: a try of an order
  // already placed gets its answer again, and one still under way (or left uncertain) is charged
  // and placed no second time.
  const stub = sheetStub(env, key);
  let begun;
  try {
    const answer = await stub.fetch("https://sheet/begin", {
      method: "POST",
      headers: { "x-days": String(SHEET_DAYS) },
      body: await file.arrayBuffer(),
    });
    if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
    begun = await answer.json();
  } catch (error) {
    log("Keeping the sheet failed", error);
    return bare(502);
  }
  if (begun.state === "placed") return placedAnswer(env, provider, begun.order, begun.charge);
  if (begun.state !== "new") {
    log(`Order ${key} is ${begun.state} already (payment ${begun.charge ?? "none"})`);
    return json(202, { ok: false, pending: true });
  }

  let charge = null;
  if (payment) {
    let priced;
    try {
      priced = await priceOf(env, deps, provider, code, recipient.country);
    } catch (error) {
      log("Pricing the order failed", error);
      await drop(stub);
      return bare(502);
    }
    // The painter agreed to the price on screen: a price that moved since is asked again.
    if (money(priced.price) !== body.price || priced.currency !== body.currency) {
      await drop(stub);
      return bare(409);
    }
    await mark(stub, { state: "charging" });
    try {
      charge = await chargeApplePay(env, deps, payment, priced, key);
    } catch (error) {
      if (error?.uncertain) {
        // Stripe may have charged: the order stays "charging", so no try charges it again.
        log(`Stripe may have charged order ${key}: look it up by metadata[sheet]`, error);
        return json(202, { ok: false, pending: true });
      }
      log("Charging the order failed", error);
      await drop(stub);
      return bare(error?.declined ? 402 : 502);
    }
    await mark(stub, { state: "charged", charge });
  }

  const origin = new URL(request.url).origin;
  await mark(stub, { state: "placing", charge });
  let orderId;
  try {
    orderId = await provider.place(env, deps, {
      reference: `sheet-${key.slice(0, 12)}`, key, code, recipient, sheetUrl: `${origin}${SHEETS}${key}/${begun.token}.pdf`,
    });
  } catch (error) {
    if (error?.uncertain) {
      // The service may have taken it: the sheet and the payment stay, the log has them for a look by hand.
      log(`${provider.name} may hold order ${key} (payment ${charge ?? "none"})`, error);
      return json(202, { ok: false, pending: true });
    }
    log("Placing the order failed", error);
    await drop(stub);
    await refund(env, deps, charge, key);
    return bare(502);
  }
  await mark(stub, { state: "placed", charge, order: orderId });
  return placedAnswer(env, provider, orderId, charge);
}

function placedAnswer(env, provider, orderId, charge) {
  return json(201, { ok: true, order: orderId, sandbox: provider.isSandbox(env), paid: Boolean(charge) });
}

/** Records where an order stands; a failure is logged and leaves the state before it, which is the safer. */
async function mark(stub, state) {
  try {
    const answer = await stub.fetch("https://sheet/mark", { method: "POST", body: JSON.stringify(state) });
    if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
  } catch (error) {
    log(`Recording an order as ${state.state} failed`, error);
  }
}

async function drop(stub) {
  try {
    await stub.fetch("https://sheet/drop", { method: "POST" });
  } catch (error) {
    log("Dropping a sheet failed", error);
  }
}

/** A form part as text: a plain field, or a file part (the app sends `order.json`), or null. */
async function partText(part, limit) {
  if (typeof part === "string") return part.length <= limit ? part : null;
  if (!isBlob(part) || part.size > limit) return null;
  return await part.text();
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
  if (typeof data !== "string" || data.length === 0 || data.length > 24576 || !/^[A-Za-z0-9+/=]+$/.test(data)) return null;
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
async function chargeApplePay(env, deps, payment, priced, key) {
  const pkToken = Buffer.from(payment.data, "base64").toString("utf8");
  const token = await stripe(env, deps, "/tokens", `${key}-token`, {
    pk_token: pkToken,
    pk_token_instrument_name: payment.instrument,
    pk_token_payment_network: payment.network,
    pk_token_transaction_id: payment.transactionId,
  });
  if (typeof token?.id !== "string") throw new Error("Stripe made no token");
  const intent = await stripe(env, deps, "/payment_intents", `${key}-intent`, {
    amount: String(minorUnits(priced.price, priced.currency)),
    currency: priced.currency.toLowerCase(),
    confirm: "true",
    "payment_method_types[]": "card",
    "payment_method_data[type]": "card",
    "payment_method_data[card][token]": token.id,
    description: "One Big Sheet",
    "metadata[sheet]": key,
  });
  if (typeof intent?.id !== "string") throw Object.assign(new Error("Stripe's answer had no payment"), { uncertain: true });
  if (intent.status !== "succeeded") {
    // requires_action and the like: nothing was taken, and Apple Pay's sheet is gone.
    throw Object.assign(new Error(`Stripe's payment is ${intent.status}`), { declined: true });
  }
  return intent.id;
}

/** Gives a payment back (an order that couldn't be placed after it); logs what it can't. */
async function refund(env, deps, charge, key) {
  if (!charge) return;
  try {
    await stripe(env, deps, "/refunds", `${key}-refund`, { payment_intent: charge });
  } catch (error) {
    log(`Refunding ${charge} failed`, error);
  }
}

/**
 * One call of Stripe's API, under an idempotency key, so the same call made again is answered as
 * before. An error that leaves it unknown whether Stripe acted (no answer, a 5xx) is `uncertain`.
 */
async function stripe(env, deps, path, idempotencyKey, fields) {
  const fetcher = deps.fetch ?? fetch;
  let response, text;
  try {
    response = await fetcher(`${STRIPE}${path}`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
        "content-type": "application/x-www-form-urlencoded",
        "idempotency-key": idempotencyKey,
      },
      body: new URLSearchParams(fields).toString(),
    });
    text = await response.text();
  } catch (error) {
    throw Object.assign(new Error(`Stripe ${path}: ${error?.message ?? error}`), { uncertain: true });
  }
  if (response.status >= 500) throw Object.assign(new Error(`Stripe ${path}: HTTP ${response.status}`), { uncertain: true });
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
 * One order's sheet and where the order stands, a Durable Object named by the app's key for the
 * order: the PDF in chunks (a stored value is at most 2 MB), its random token, the state ("new",
 * "charging", "charged", "placing", "placed") with the payment and order ids, and an alarm that
 * deletes it all.
 *   POST https://sheet/begin  the PDF as the body; x-days. Keeps it, unless the order is kept
 *                             already: answers {state, token, charge?, order?} as it stood
 *   POST https://sheet/mark   {state, charge?, order?}
 *   GET  https://sheet/read   x-token; the PDF, or 404
 *   POST https://sheet/drop   deletes it now (an order that surely failed)
 */
export class PrintSheet {
  constructor(state) {
    this.storage = state.storage;
  }

  async fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/begin" && request.method === "POST") {
      const days = Number(request.headers.get("x-days"));
      if (!(days > 0)) return bare(400);
      // The body first: storage calls hold the object's input gate, so between the look and the
      // write below no other try of the order runs; reading a request body doesn't.
      const bytes = new Uint8Array(await request.arrayBuffer());
      const kept = await this.storage.get(["token", "state", "charge", "order"]);
      if (kept.get("token")) {
        return json(200, { token: kept.get("token"), state: kept.get("state"), charge: kept.get("charge"), order: kept.get("order") });
      }
      const token = randomHex();
      const chunks = Math.ceil(bytes.byteLength / CHUNK);
      // A put takes at most 128 keys: a sheet is at most 25 chunks.
      const entries = { chunks };
      for (let i = 0; i < chunks; i++) entries[`chunk-${i}`] = bytes.slice(i * CHUNK, (i + 1) * CHUNK);
      await this.storage.put(entries);
      // The token last: a sheet with a token is whole.
      await this.storage.put({ token, state: "new" });
      await this.storage.setAlarm(Date.now() + days * 24 * 3600 * 1000);
      return json(201, { token, state: "new" });
    }
    if (pathname === "/mark" && request.method === "POST") {
      let next;
      try {
        next = JSON.parse(await request.text());
      } catch {
        return bare(400);
      }
      if (!(await this.storage.get("token")) || typeof next?.state !== "string") return bare(404);
      const entries = { state: next.state };
      if (typeof next.charge === "string") entries.charge = next.charge;
      if (typeof next.order === "string") entries.order = next.order;
      await this.storage.put(entries);
      return json(200, { ok: true });
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
      await this.storage.deleteAlarm?.();
      return json(200, { ok: true });
    }
    return bare(404);
  }

  async alarm() {
    await this.storage.deleteAll();
  }
}

// MARK: Prodigi's API

/** One call of Prodigi's API; no answer, or a 5xx, is `uncertain` (it may have acted). */
async function prodigiCall(env, deps, method, path, body) {
  const fetcher = deps.fetch ?? fetch;
  let response, text;
  try {
    response = await fetcher(`${env.PRODIGI_API}${path}`, {
      method,
      headers: { "x-api-key": env.PRODIGI_API_KEY, "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    text = await response.text();
  } catch (error) {
    throw Object.assign(new Error(`Prodigi ${method} ${path}: ${error?.message ?? error}`), { uncertain: true });
  }
  if (!response.ok) {
    // Its outcome alone: the body may echo the address, which is kept nowhere here.
    let outcome = "";
    try {
      outcome = String(JSON.parse(text)?.outcome ?? "").slice(0, 60);
    } catch {}
    const error = new Error(`Prodigi ${method} ${path}: HTTP ${response.status} ${outcome}`);
    throw Object.assign(error, { uncertain: response.status >= 500 });
  }
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
