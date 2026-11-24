// Tests of One Big Sheet's part of the relay (print.js) against a mocked Prodigi and an in-memory
// Durable Object. `node --test feedback-relay/print.test.js`; CI's `core` job runs it.

import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { webcrypto } from "node:crypto";
import { test } from "node:test";

import { cleanPayment, cleanRecipient, handlePrint, minorUnits, priceFor, PrintSheet, PRODUCTS, reconcilePrints } from "./print.js";
import { handle } from "./worker.js";

globalThis.crypto ??= webcrypto;

const SANDBOX = "https://api.prodigi.com/v5";
const STRIPE = "https://api.stripe.com/v1";
const KEY = "prodigi-sandbox-SECRET";
const ID = "0123456789abcdef0123456789abcdef";
const PDF = new TextEncoder().encode("%PDF-1.7\n%stand-in for a sheet\n");
const RECIPIENT = {
  name: "Ada Painter", email: "ada@example.com", line1: "1 Moon Lane", city: "Brooklyn", state: "NY", zip: "11201", country: "US",
};

// MARK: Fakes

/**
 * A Durable Object namespace holding PrintSheets in memory; alarms are recorded, rung by hand.
 * `env` and `deps` are what each object's alarm works with (set by `env()` and the tests).
 */
function sheetsNamespace() {
  const objects = new Map();
  const namespace = {
    objects,
    env: {},
    deps: {},
    idFromName: (name) => name,
    get(id) {
      if (!objects.has(id)) {
        const data = new Map();
        const storage = {
          alarm: null,
          async get(key) {
            return Array.isArray(key) ? new Map(key.filter((k) => data.has(k)).map((k) => [k, data.get(k)])) : data.get(key);
          },
          async put(entries) { for (const [k, v] of Object.entries(entries)) data.set(k, v); },
          async delete(key) { data.delete(key); },
          async deleteAll() { data.clear(); storage.alarm = null; },
          async setAlarm(at) { storage.alarm = at; },
          async deleteAlarm() { storage.alarm = null; },
          data,
        };
        const sheet = new PrintSheet({ storage }, namespace.env, namespace.deps);
        // As a stub does: the call becomes a Request.
        objects.set(id, { storage, alarm: () => sheet.alarm(), fetch: (url, init) => sheet.fetch(new Request(url, init)) });
      }
      return objects.get(id);
    },
  };
  return namespace;
}

/** A clock the tests move: the relay's and every object's `now`. */
function clock(start = Date.UTC(2026, 10, 24, 12)) {
  const c = { t: start, now: () => c.t };
  return c;
}

/**
 * Rings an order's alarm, moving the clock to each, until the order settles (or `rings` run out);
 * answers its state.
 */
async function settle(e, c, rings = 12) {
  const object = e.PRINT_SHEETS.get(ID);
  for (let i = 0; i < rings; i++) {
    const state = object.storage.data.get("state");
    if (!["charging", "queued", "charged", "placing", "placed"].includes(state) || object.storage.alarm === null) break;
    c.t = Math.max(c.t, object.storage.alarm);
    await object.alarm();
  }
  return object.storage.data.get("state");
}

/** A fetch standing in for Prodigi (and Stripe): records each call and answers from `routes`. */
function prodigi(routes) {
  const calls = [];
  const fetcher = async (url, init) => {
    const stripe = url.startsWith(STRIPE);
    calls.push({ url, init, body: init?.body ? (stripe ? Object.fromEntries(new URLSearchParams(init.body)) : JSON.parse(init.body)) : undefined });
    const github = url.startsWith("https://api.github.com");
    const path = stripe ? `stripe:${url.slice(STRIPE.length).split("?")[0]}`
      : github ? `github:${url.slice("https://api.github.com".length)}` : url.slice(SANDBOX.length);
    const answer = routes[path] ?? (github ? { number: 1 } : undefined);
    if (!answer) return new Response("not found", { status: 404 });
    return typeof answer === "function" ? answer() : new Response(JSON.stringify(answer), { status: 200 });
  };
  return { calls, fetcher };
}

const QUOTE = {
  data: { items: { amount: "14.00", currency: "USD" }, shipping: { amount: "9.29", currency: "USD" }, total: { amount: "23.29", currency: "USD" } },
};
const PLACED = { data: { id: "ord_123456", status: "pending_submission" } };
const TAKEN = { data: { id: "ord_123456", status: "in_production", issues: [] } };

function env(overrides = {}) {
  const e = {
    PRODIGI_API: SANDBOX, PRODIGI_API_KEY: KEY, MARKUP: "0.4", PRINT_SHEETS: sheetsNamespace(),
    FEEDBACK_REPO: "owner/feedback", FEEDBACK_GITHUB_TOKEN: "ghp_SECRET", ...overrides,
  };
  if (e.PRINT_SHEETS) e.PRINT_SHEETS.env = e;
  return e;
}

/** The env, a clock and deps sharing a fetch, the relay's and every order object's. */
function world(routes, overrides = {}) {
  const e = env(overrides);
  const c = clock();
  const p = prodigi(routes);
  const deps = { fetch: p.fetcher, now: c.now };
  Object.assign(e.PRINT_SHEETS.deps, deps);
  return { e, c, calls: p.calls, deps };
}

function quoteRequest(body, headers = {}) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return new Request("https://relay.example/v1/print/quotes", {
    method: "POST",
    headers: { "content-type": "application/json", "content-length": String(text.length), ...headers },
    body: text,
  });
}

const ORDER = { key: ID, product: "canvas-16x24", recipient: RECIPIENT };

/** An order as the app sends it: the order a file part, `order.json` (or a plain field, `plain`). */
async function orderRequest({ sheet = PDF, order = ORDER, plain = false } = {}) {
  const form = new FormData();
  if (sheet) form.append("sheet", new Blob([sheet], { type: "application/pdf" }), "sheet.pdf");
  if (order) {
    const text = typeof order === "string" ? order : JSON.stringify(order);
    if (plain) form.append("order", text);
    else form.append("order", new Blob([text], { type: "application/json" }), "order.json");
  }
  const encoded = new Response(form);
  const body = await encoded.arrayBuffer();
  return new Request("https://relay.example/v1/print/orders", {
    method: "POST",
    headers: { "content-type": encoded.headers.get("content-type"), "content-length": String(body.byteLength) },
    body,
  });
}

// MARK: Quotes

test("a quote is Prodigi's cost with the markup, rounded up, and says the cut in the sandbox", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE });
  const answer = await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), env(), { fetch: fetcher });
  assert.equal(answer.status, 200);
  assert.deepEqual(await answer.json(), {
    product: "canvas-16x24", currency: "USD", price: "33.00", sandbox: { cost: "23.29", cut: "9.71" },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${SANDBOX}/quotes/order`);
  assert.equal(calls[0].init.headers["x-api-key"], `sandbox_${KEY}`);
  assert.deepEqual(calls[0].body.items[0].catalogueVariantId, PRODUCTS["canvas-16x24"]);
  assert.equal(calls[0].body.shippingAddress.countryCode, "US");
  assert.equal(calls[0].body.shippingMethod, "standard");
});

test("a quote for an unknown product or a malformed country is refused before Prodigi", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE });
  for (const body of [{ product: "mug", country: "US" }, { product: "canvas-16x24", country: "usa" }, { product: "canvas-16x24" }, "not json"]) {
    const answer = await handlePrint(quoteRequest(body), env(), { fetch: fetcher });
    assert.equal(answer.status, 400, JSON.stringify(body));
  }
  assert.equal(calls.length, 0);
});

test("a quote that isn't JSON, or too large, is refused", async () => {
  const wrongType = await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }, { "content-type": "text/plain" }), env());
  assert.equal(wrongType.status, 415);
  const big = await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US", pad: "x".repeat(2000) }), env());
  assert.equal(big.status, 413);
});

test("Prodigi refusing, or answering without a total, is a 502", async () => {
  const refused = prodigi({ "/quotes/order": () => new Response("{}", { status: 400 }) });
  assert.equal((await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), env(), { fetch: refused.fetcher })).status, 502);
  const empty = prodigi({ "/quotes/order": { data: {} } });
  assert.equal((await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), env(), { fetch: empty.fetcher })).status, 502);
});

test("the price rounds up to a whole unit, and a bad markup falls back to 40%", () => {
  assert.equal(priceFor(10, "0.4"), 14);
  assert.equal(priceFor(10.01, "0.4"), 15);
  assert.equal(priceFor(10, "nonsense"), 14);
  assert.equal(priceFor(10, "-1"), 14);
  assert.equal(priceFor(10, "0"), 10);
});

// MARK: Only the sandbox

test("the relay never talks to Prodigi's live API: it would print at Paul's cost", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE, "/orders": PLACED });
  for (const live of [env({ PRODIGI_API: "https://api.prodigi.com/v4.0" }), env({ PRODIGI_API_KEY: "live_REAL" })]) {
    assert.equal((await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), live, { fetch: fetcher })).status, 503);
    assert.equal((await handlePrint(await orderRequest(), live, { fetch: fetcher })).status, 503);
  }
  assert.equal(calls.length, 0);
});

test("a sandbox key already prefixed is sent as it is", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE });
  await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), env({ PRODIGI_API_KEY: "sandbox_abc" }), { fetch: fetcher });
  assert.equal(calls[0].init.headers["x-api-key"], "sandbox_abc");
});

test("without its key or storage the relay says it is misconfigured", async () => {
  for (const missing of ["PRODIGI_API_KEY", "PRODIGI_API", "PRINT_SHEETS"]) {
    const answer = await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), env({ [missing]: undefined }));
    assert.equal(answer.status, 500, missing);
  }
});

test("a flood is braked", async () => {
  const limiter = { limit: async () => ({ success: false }) };
  const answer = await handlePrint(quoteRequest({ product: "canvas-16x24", country: "US" }), env({ PRINT_LIMITER: limiter }));
  assert.equal(answer.status, 429);
});

// MARK: Orders

test("a large sheet is kept in chunks and comes back whole", async () => {
  const big = new Uint8Array(2.5 * 1024 * 1024);
  big.set(new TextEncoder().encode("%PDF-"));
  for (let i = 5; i < big.length; i++) big[i] = i % 251;
  const e = env();
    const { fetcher } = prodigi({ "/orders": PLACED });
  assert.equal((await handlePrint(await orderRequest({ sheet: big }), e, { fetch: fetcher })).status, 201);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("chunks"), 3);
  const token = e.PRINT_SHEETS.get(ID).storage.data.get("token");
  const fetched = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${token}.pdf`), e);
  assert.deepEqual(new Uint8Array(await fetched.arrayBuffer()), big);
});

test("an order without a PDF, with a bad recipient or an unknown product is refused before Prodigi", async () => {
  const { calls, fetcher } = prodigi({ "/orders": PLACED });
  const cases = [
    [{ sheet: new TextEncoder().encode("\x89PNG....") }, 415],
    [{ sheet: null }, 400],
    [{ order: null }, 400],
    [{ order: "{" }, 400],
    [{ order: { ...ORDER, product: "mug" } }, 400],
    [{ order: { ...ORDER, recipient: { ...RECIPIENT, email: "nope" } } }, 400],
    [{ order: { ...ORDER, recipient: { ...RECIPIENT, zip: "" } } }, 400],
    [{ order: { ...ORDER, key: undefined } }, 400],
    [{ order: { ...ORDER, key: "../x" } }, 400],
    [{ order: JSON.stringify({ ...ORDER, pad: "x".repeat(40000) }) }, 400],
  ];
  for (const [parts, status] of cases) {
    assert.equal((await handlePrint(await orderRequest(parts), env(), { fetch: fetcher })).status, status, JSON.stringify(parts));
  }
  assert.equal(calls.length, 0);
});

test("the recipient's fields are trimmed, control characters dropped and lengths capped", () => {
  assert.deepEqual(cleanRecipient({ ...RECIPIENT, name: "  Ada\u0007 Painter ", line2: undefined }), {
    ...RECIPIENT, name: "Ada  Painter", line2: "",
  });
  assert.equal(cleanRecipient({ ...RECIPIENT, line1: "x".repeat(201) }), null);
  assert.equal(cleanRecipient({ ...RECIPIENT, city: 7 }), null);
  assert.equal(cleanRecipient(null), null);
  assert.equal(cleanRecipient({ ...RECIPIENT, state: undefined }).state, "");
});

test("other paths and methods", async () => {
  assert.equal((await handle(new Request("https://relay.example/v1/print/other", { method: "POST" }), env())).status, 404);
  assert.equal((await handle(new Request("https://relay.example/v1/print/quotes"), env())).status, 405);
  assert.equal((await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${ID}.pdf`, { method: "POST" }), env())).status, 405);
});

// MARK: Payment

const PAYMENT = {
  data: Buffer.from('{"version":"EC_v1","data":"…"}').toString("base64"),
  network: "Visa", transactionId: "abc123", instrument: "Visa 4242",
};
const PAID_ORDER = { ...ORDER, price: "33.00", currency: "USD", payment: PAYMENT };
const STRIPE_ENV = { STRIPE_SECRET_KEY: "sk_test_SECRET" };

test("a restricted test key charges too", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes/order": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env({ STRIPE_SECRET_KEY: "rk_test_SECRET" }), { fetch: fetcher });
  assert.equal(answer.status, 201);
  assert.equal(calls[1].init.headers.authorization, "Bearer rk_test_SECRET");
});

test("with Stripe, an order without a payment, or at a price that moved, is not placed", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE, "/orders": PLACED });
  const unpaid = await handlePrint(await orderRequest(), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(unpaid.status, 402);
  const moved = await handlePrint(await orderRequest({ order: { ...PAID_ORDER, price: "30.00" } }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(moved.status, 409);
  assert.ok(!calls.some((c) => c.url.endsWith("/orders") || c.url.startsWith(STRIPE)));
});

test("a declined card is a 402 and places nothing", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes/order": QUOTE, "/orders": PLACED, "stripe:/tokens": { id: "tok_1" },
    "stripe:/payment_intents": () => new Response('{"error":{"type":"card_error","code":"card_declined"}}', { status: 402 }),
  });
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(answer.status, 402);
  assert.ok(!calls.some((c) => c.url === `${SANDBOX}/orders`));
});

test("a live Stripe key is never used against the sandbox printer", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE, "/orders": PLACED });
  for (const live of ["sk_live_REAL", "rk_live_REAL"]) {
    const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env({ STRIPE_SECRET_KEY: live }), { fetch: fetcher });
    assert.equal(answer.status, 503);
  }
  assert.equal(calls.length, 0);
});

test("payments and amounts are checked", () => {
  assert.equal(cleanPayment({ ...PAYMENT, data: "not base64!" }), null);
  assert.equal(cleanPayment({ ...PAYMENT, network: 4 }), null);
  assert.equal(cleanPayment(null), null);
  assert.deepEqual(cleanPayment({ data: "QQ==" }), { data: "QQ==", network: "", transactionId: "", instrument: "" });
  assert.equal(minorUnits(33, "USD"), 3300);
  assert.equal(minorUnits(33.1, "eur"), 3310);
  assert.equal(minorUnits(4200, "JPY"), 4200);
});

// MARK: Once per order

test("the order as a plain form field is read too", async () => {
  const { fetcher } = prodigi({ "/orders": PLACED });
  assert.equal((await handlePrint(await orderRequest({ plain: true }), env(), { fetch: fetcher })).status, 201);
});

test("an Apple Pay token of several KB fits", async () => {
  const { fetcher } = prodigi({
    "/quotes/order": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  const payment = { ...PAYMENT, data: Buffer.from("x".repeat(6000)).toString("base64") };
  const answer = await handlePrint(await orderRequest({ order: { ...PAID_ORDER, payment } }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(answer.status, 201);
});

test("Stripe's calls carry the order's idempotency keys", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes/order": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  await handlePrint(await orderRequest({ order: PAID_ORDER }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(calls[1].init.headers["idempotency-key"], `${ID}-token`);
  assert.equal(calls[2].init.headers["idempotency-key"], `${ID}-intent`);
  assert.equal(calls[2].body["metadata[sheet]"], ID);
});

test("the sheet's store failing charges nothing", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE, "/orders": PLACED });
  const e = env(STRIPE_ENV);
  e.PRINT_SHEETS = { idFromName: (n) => n, get: () => ({ fetch: async () => { throw new Error("overloaded"); } }) };
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher })).status, 502);
  assert.equal(calls.length, 0);
});

// MARK: The order's own alarm places it, checks it was taken, refunds it if not

const PAID = {
  "/quotes/order": QUOTE, "/orders": PLACED, "/orders/ord_123456": TAKEN,
  "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" }, "stripe:/refunds": { id: "re_1" },
};

test("an order is taken at once and placed by its alarm, with the sheet's URL Prodigi can fetch", async () => {
  const { e, c, calls, deps } = world({ "/orders": PLACED, "/orders/ord_123456": TAKEN });
  const answer = await handlePrint(await orderRequest(), e, deps);
  assert.equal(answer.status, 201);
  assert.deepEqual(await answer.json(), { ok: true, order: `sheet-${ID.slice(0, 12)}`, sandbox: true, paid: false });
  assert.equal(calls.length, 0);
  const storage = e.PRINT_SHEETS.get(ID).storage;
  assert.equal(storage.data.get("state"), "queued");
  assert.equal(storage.alarm, c.t);

  assert.equal(await settle(e, c), "accepted");
  const sent = calls.find((call) => call.url === `${SANDBOX}/orders`);
  assert.equal(sent.body.items[0].sku, "GLOBAL-CAN-ROL-SC-16X24");
  assert.equal(sent.body.submit, true);
  assert.equal(sent.init.headers["idempotency-key"], ID);
  assert.equal(sent.body.recipient.address.postalOrZipCode, "11201");
  assert.equal(sent.body.merchantReference, `sheet-${ID.slice(0, 12)}`);
  const token = storage.data.get("token");
  const url = sent.body.items[0].assets[0].url;
  assert.equal(url, `https://relay.example/v1/print/sheets/${ID}/${token}.pdf`);
  assert.ok(calls.some((call) => call.url === `${SANDBOX}/orders/ord_123456` && call.init.method === "GET"));
  // Accepted: the address leaves the relay; the sheet stays for the printer, two weeks.
  assert.equal(storage.data.get("job").recipient, undefined);
  assert.equal(storage.data.get("order"), "ord_123456");
  const fetched = await handle(new Request(url), e);
  assert.equal(fetched.status, 200);
  assert.deepEqual(new Uint8Array(await fetched.arrayBuffer()), PDF);
  assert.ok(storage.alarm > c.t + 13 * 24 * 3600 * 1000);
  c.t = storage.alarm;
  await e.PRINT_SHEETS.get(ID).alarm();
  assert.equal((await handle(new Request(url), e)).status, 404);
});

test("a kept sheet answers only its own token", async () => {
  const { e, c, deps } = world({ "/orders": PLACED, "/orders/ord_123456": TAKEN });
  await handlePrint(await orderRequest(), e, deps);
  await settle(e, c);
  const wrong = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${"0".repeat(32)}.pdf`), e);
  assert.equal(wrong.status, 404);
  const malformed = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/../x.pdf`), e);
  assert.equal(malformed.status, 404);
});

test("a large sheet is kept in chunks and comes back whole", async () => {
  const big = new Uint8Array(2.5 * 1024 * 1024);
  big.set(new TextEncoder().encode("%PDF-"));
  for (let i = 5; i < big.length; i++) big[i] = i % 251;
  const { e, deps } = world({});
  assert.equal((await handlePrint(await orderRequest({ sheet: big }), e, deps)).status, 201);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("chunks"), 3);
  const token = e.PRINT_SHEETS.get(ID).storage.data.get("token");
  const fetched = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${token}.pdf`), e);
  assert.deepEqual(new Uint8Array(await fetched.arrayBuffer()), big);
});

test("the sheet goes up first, then the order as JSON alone; an order with no sheet kept asks for it", async () => {
  const { e, deps } = world(PAID, STRIPE_ENV);
  const json = (order) => new Request("https://relay.example/v1/print/orders", {
    method: "POST", headers: { "content-type": "application/json", "content-length": String(JSON.stringify(order).length) }, body: JSON.stringify(order),
  });
  assert.equal((await handlePrint(json(PAID_ORDER), e, deps)).status, 412);
  const put = (body, type = "application/pdf") => new Request(`https://relay.example/v1/print/sheets/${ID}`, {
    method: "PUT", headers: { "content-type": type, "content-length": String(body.byteLength) }, body,
  });
  assert.equal((await handlePrint(put(new TextEncoder().encode("GIF89a")), e, deps)).status, 415);
  assert.equal((await handlePrint(put(PDF, "text/plain"), e, deps)).status, 415);
  assert.equal((await handlePrint(put(PDF), e, deps)).status, 200);
  const answer = await handlePrint(json(PAID_ORDER), e, deps);
  assert.equal(answer.status, 201);
  assert.equal((await answer.json()).paid, true);
  // Once ordered, the sheet stays as it was ordered.
  assert.equal((await handlePrint(put(new TextEncoder().encode("%PDF-other")), e, deps)).status, 200);
  const token = e.PRINT_SHEETS.get(ID).storage.data.get("token");
  const fetched = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${token}.pdf`), e);
  assert.deepEqual(new Uint8Array(await fetched.arrayBuffer()), PDF);
  assert.equal((await handlePrint(new Request(`https://relay.example/v1/print/sheets/${ID}`, { method: "POST" }), e, deps)).status, 405);
});

test("with Stripe, the order is charged the agreed price through Apple Pay, and answered before it is placed", async () => {
  const { e, c, calls, deps } = world(PAID, STRIPE_ENV);
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(answer.status, 201);
  assert.deepEqual(await answer.json(), { ok: true, order: `sheet-${ID.slice(0, 12)}`, sandbox: true, paid: true });
  assert.deepEqual(calls.map((call) => call.url), [`${SANDBOX}/quotes/order`, `${STRIPE}/tokens`, `${STRIPE}/payment_intents`]);
  assert.equal(calls[1].init.headers.authorization, "Bearer sk_test_SECRET");
  assert.equal(calls[1].body.pk_token, '{"version":"EC_v1","data":"…"}');
  assert.equal(calls[1].body.pk_token_payment_network, "Visa");
  assert.equal(calls[2].body.amount, "3300");
  assert.equal(calls[2].body.currency, "usd");
  assert.equal(calls[2].body["payment_method_data[card][token]"], "tok_1");
  assert.equal(calls[2].body.confirm, "true");
  assert.equal(calls[2].body["automatic_payment_methods[allow_redirects]"], "never");
  assert.equal(calls[2].body.receipt_email, "ada@example.com");
  assert.equal(calls[2].body["shipping[name]"], "Ada Painter");
  assert.equal(calls[2].body["shipping[address][postal_code]"], "11201");
  assert.equal(calls[2].body["shipping[address][line2]"], undefined);
  // Priced where it goes.
  assert.equal(calls[0].body.shippingAddress.postalOrZipCode, "11201");
  assert.equal(calls[0].body.shippingAddress.stateOrCounty, "NY");
  assert.equal(calls[0].body.shippingAddress.townOrCity, "Brooklyn");
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("state"), "charged");
  assert.equal(await settle(e, c), "accepted");
  assert.ok(calls.some((call) => call.url === `${SANDBOX}/orders`));
  assert.ok(!calls.some((call) => call.url === `${STRIPE}/refunds`));
});

test("an order taken already is answered again, with nothing charged or placed twice", async () => {
  const { e, c, calls, deps } = world(PAID, STRIPE_ENV);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 201);
  await settle(e, c);
  const made = calls.length;
  const again = await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(again.status, 201);
  assert.deepEqual(await again.json(), { ok: true, order: `sheet-${ID.slice(0, 12)}`, sandbox: true, paid: true });
  assert.equal(calls.length, made);
});

test("an order Prodigi refuses when placed is refunded, Paul is told, and a try of it is answered gone", async () => {
  const { e, c, calls, deps } = world({ ...PAID, "/orders": () => new Response('{"type":"validation_error"}', { status: 400 }) }, STRIPE_ENV);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 201);
  assert.equal(await settle(e, c), "refused");
  const refund = calls.find((call) => call.url === `${STRIPE}/refunds`);
  assert.equal(refund?.body.payment_intent, "pi_1");
  assert.equal(refund?.init.headers["idempotency-key"], `${ID}-refund`);
  const issues = calls.filter((call) => call.url === "https://api.github.com/repos/owner/feedback/issues");
  assert.equal(issues.length, 1);
  assert.match(issues[0].body.title, /refused/);
  assert.match(issues[0].body.body, /pi_1/);
  assert.match(issues[0].body.body, /dashboard\.stripe\.com\/test\/payments\/pi_1/);
  assert.doesNotMatch(issues[0].body.body, /Ada|Moon Lane|ada@example/);
  assert.equal(issues[0].init.headers.authorization, "Bearer ghp_SECRET");
  const again = await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(again.status, 410);
  assert.deepEqual(await again.json(), { ok: false, refused: true, refunded: true });
});

test("an order Prodigi turns down after taking it is refunded too", async () => {
  const refused = { data: { id: "ord_123456", status: "draft", issues: [{ code: "fulfilment_issue", message: "x" }] } };
  const { e, c, calls, deps } = world({ ...PAID, "/orders/ord_123456": refused }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c), "refused");
  assert.ok(calls.some((call) => call.url === `${STRIPE}/refunds`));
});

test("a refund that fails says so in the issue", async () => {
  const { e, c, calls, deps } = world({
    ...PAID, "/orders": () => new Response("{}", { status: 400 }), "stripe:/refunds": () => new Response('{"error":{}}', { status: 400 }),
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  await settle(e, c);
  const issue = calls.find((call) => call.url.endsWith("/issues"));
  assert.match(issue.body.title, /refund failed/);
  assert.match(issue.body.body, /FAILED/);
});

test("Prodigi not answering is tried again, a minute and then longer, until it places", async () => {
  let down = 3;
  const { e, c, calls, deps } = world({
    ...PAID, "/orders": () => (down-- > 0 ? new Response("{}", { status: 503 }) : new Response(JSON.stringify(PLACED), { status: 202 })),
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  const start = c.t;
  assert.equal(await settle(e, c), "accepted");
  assert.equal(calls.filter((call) => call.url === `${SANDBOX}/orders`).length, 4);
  assert.ok(c.t - start >= (1 + 2 + 4) * 60_000);
  assert.ok(!calls.some((call) => call.url.endsWith("/refunds") || call.url.endsWith("/issues")));
});

test("a placed order not readable yet, or still submitting, is checked again", async () => {
  let reads = 0;
  const { e, c, calls, deps } = world({
    "/orders": PLACED,
    "/orders/ord_123456": () => (++reads === 1 ? new Response("{}", { status: 404 })
      : reads === 2 ? new Response(JSON.stringify(PLACED), { status: 200 }) : new Response(JSON.stringify(TAKEN), { status: 200 })),
  });
  await handlePrint(await orderRequest(), e, deps);
  assert.equal(await settle(e, c), "accepted");
  assert.equal(reads, 3);
  assert.ok(!calls.some((call) => call.url.endsWith("/issues")));
});

test("an order on hold tells Paul once and keeps checking", async () => {
  const held = { data: { id: "ord_123456", status: "on_hold", issues: [{ code: "payment_required" }] } };
  const { e, c, calls, deps } = world({ ...PAID, "/orders/ord_123456": held }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c, 6), "placed");
  const issues = calls.filter((call) => call.url.endsWith("/issues"));
  assert.equal(issues.length, 1);
  assert.match(issues[0].body.body, /payment_required/);
  assert.ok(!calls.some((call) => call.url.endsWith("/refunds")));
});

test("an order that won't settle in two days is given up, and Paul told", async () => {
  const { e, c, calls, deps } = world({ ...PAID, "/orders": () => new Response("{}", { status: 503 }) }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c, 80), "stuck");
  const issue = calls.find((call) => call.url.endsWith("/issues"));
  assert.match(issue.body.title, /stopped trying/);
  assert.ok(!calls.some((call) => call.url.endsWith("/refunds")));
});

test("Stripe not answering leaves the order charging; its alarm finds the payment and places it", async () => {
  let payments = 0;
  const { e, c, calls, deps } = world({
    ...PAID,
    "stripe:/payment_intents": () => { payments++; throw new TypeError("network connection lost"); },
    "stripe:/payment_intents/search": { data: [{ id: "pi_9", status: "succeeded" }] },
  }, STRIPE_ENV);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 202);
  const storage = e.PRINT_SHEETS.get(ID).storage;
  assert.equal(storage.data.get("state"), "charging");
  // A second try of it charges nothing.
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 202);
  assert.equal(payments, 1);
  assert.equal(storage.alarm, c.t + 5 * 60_000);
  assert.equal(await settle(e, c), "accepted");
  assert.equal(storage.data.get("charge"), "pi_9");
  const search = calls.find((call) => call.url.startsWith(`${STRIPE}/payment_intents/search`));
  assert.match(decodeURIComponent(search.url), new RegExp(`metadata\\['sheet'\\]:'${ID}'`));
});

test("a payment Stripe never took lets the order go, to be tried again", async () => {
  const { e, c, deps } = world({
    ...PAID,
    "stripe:/payment_intents": () => { throw new TypeError("network connection lost"); },
    "stripe:/payment_intents/search": { data: [] },
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c), "new");
  const storage = e.PRINT_SHEETS.get(ID).storage;
  assert.equal(storage.data.get("job"), undefined);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 202);
});

test("an order that surely failed before the charge can be tried again under its key", async () => {
  let declined = true;
  const { e, deps } = world({
    ...PAID,
    "stripe:/payment_intents": () => (declined
      ? new Response('{"error":{"type":"card_error","code":"card_declined"}}', { status: 402 })
      : new Response(JSON.stringify({ id: "pi_1", status: "succeeded" }), { status: 200 })),
  }, STRIPE_ENV);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 402);
  declined = false;
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps)).status, 201);
});

test("a second try while the first is still pricing waits, and its failure can't drop the first's order", async () => {
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  const { e, calls, deps } = world({
    ...PAID, "/quotes/order": async () => { await held; return new Response(JSON.stringify(QUOTE), { status: 200 }); },
  }, STRIPE_ENV);
  const first = handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  while (!calls.length) await new Promise((r) => setTimeout(r, 1));
  const second = await handlePrint(await orderRequest({ order: { ...PAID_ORDER, price: "1.00" } }), e, deps);
  assert.equal(second.status, 202);
  release();
  assert.equal((await first).status, 201);
  assert.equal(calls.filter((call) => call.url === `${STRIPE}/payment_intents`).length, 1);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("state"), "charged");
});

test("only the claim's holder marks or drops an order", async () => {
  const e = env();
  const stub = e.PRINT_SHEETS.get(ID);
  assert.equal((await stub.fetch("https://sheet/begin", { method: "POST" })).status, 404);
  await stub.fetch("https://sheet/keep", { method: "POST", headers: { "x-days": "14" }, body: PDF });
  const begun = await (await stub.fetch("https://sheet/begin", { method: "POST" })).json();
  assert.match(begun.claim, /^[0-9a-f]+$/);
  const again = await (await stub.fetch("https://sheet/begin", { method: "POST" })).json();
  assert.equal(again.claim, undefined);
  assert.equal((await stub.fetch("https://sheet/drop", { method: "POST", headers: { "x-claim": "beef" } })).status, 409);
  assert.equal((await stub.fetch("https://sheet/mark", { method: "POST", headers: { "x-claim": "beef" }, body: '{"state":"charging"}' })).status, 409);
  assert.equal(stub.storage.data.get("state"), "new");
  assert.equal((await stub.fetch("https://sheet/mark", { method: "POST", headers: { "x-claim": begun.claim }, body: '{"state":"charging"}' })).status, 200);
});

test("a claim left new by a try that went away is taken by a later try", async () => {
  const { e, c, deps } = world({});
  const stub = e.PRINT_SHEETS.get(ID);
  await stub.fetch("https://sheet/keep", { method: "POST", headers: { "x-days": "14" }, body: PDF });
  await stub.fetch("https://sheet/begin", { method: "POST" });
  assert.equal((await handlePrint(await orderRequest(), e, deps)).status, 202);
  c.t += 10 * 60 * 1000;
  assert.equal((await handlePrint(await orderRequest(), e, deps)).status, 201);
});

// MARK: Quotes where the sheet goes

test("a quote takes the city, state and postal code Apple Pay shares, and keeps a quote a while", async () => {
  const { calls, fetcher } = prodigi({ "/quotes/order": QUOTE });
  const quoteCache = new Map();
  const c = clock();
  const deps = { fetch: fetcher, quoteCache, now: c.now };
  const ask = { product: "canvas-16x24", country: "US", city: "Anchorage", state: "AK", zip: "99501" };
  assert.equal((await handlePrint(quoteRequest(ask), env(), deps)).status, 200);
  assert.deepEqual(calls[0].body.shippingAddress, { line1: "1 Main Street", townOrCity: "Anchorage", stateOrCounty: "AK", postalOrZipCode: "99501", countryCode: "US" });
  await handlePrint(quoteRequest(ask), env(), deps);
  assert.equal(calls.length, 1);
  await handlePrint(quoteRequest({ ...ask, zip: "99502" }), env(), deps);
  assert.equal(calls.length, 2);
  c.t += 11 * 60_000;
  await handlePrint(quoteRequest(ask), env(), deps);
  assert.equal(calls.length, 3);
  assert.equal((await handlePrint(quoteRequest({ ...ask, zip: 99501 }), env(), deps)).status, 400);
  assert.equal((await handlePrint(quoteRequest({ ...ask, city: "x".repeat(300) }), env(), deps)).status, 400);
});

// MARK: The daily check

test("the daily check flags a payment whose order wasn't accepted, and no other", async () => {
  const OTHER = "fedcba9876543210fedcba9876543210";
  const { e, c, calls, deps } = world(PAID, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  await settle(e, c);
  const day = Math.floor(c.t / 1000) - 7200;
  const listed = { data: [
    { id: "pi_1", status: "succeeded", created: day, metadata: { sheet: ID }, latest_charge: { refunded: false } },
    { id: "pi_3", status: "succeeded", created: day, metadata: { sheet: OTHER } },
    { id: "pi_2", status: "succeeded", created: day, metadata: { sheet: OTHER } },
    { id: "pi_4", status: "requires_payment_method", created: day, metadata: { sheet: OTHER } },
    { id: "pi_5", status: "succeeded", created: Math.floor(c.t / 1000) - 60, metadata: { sheet: OTHER } },
    { id: "pi_6", status: "succeeded", created: day, metadata: {} },
  ] };
  const refunds = () => new Response(JSON.stringify({ data: checkedRefunds.shift() ?? [] }), { status: 200 });
  const checkedRefunds = [[{ status: "succeeded" }]];
  const { calls: checked, fetcher } = prodigi({ "stripe:/payment_intents": listed, "stripe:/refunds": refunds });
  assert.equal(await reconcilePrints(e, { fetch: fetcher, now: c.now }), 1);
  const issue = checked.find((call) => call.url.endsWith("/issues"));
  assert.match(issue.body.body, /pi_2/);
  assert.match(checked[0].url, /created\[gte\]=/);
  assert.equal(calls.filter((call) => call.url.endsWith("/issues")).length, 0);
});

test("the worker runs the daily check on its schedule", async () => {
  const worker = (await import("./worker.js")).default;
  assert.equal(typeof worker.scheduled, "function");
});

test("an order is priced where the app was quoted, when that is in its country", async () => {
  const { e, calls, deps } = world(PAID, STRIPE_ENV);
  const quotedAt = { country: "US", city: "Brooklyn", state: "NY", zip: "11201" };
  await handlePrint(await orderRequest({ order: { ...PAID_ORDER, quotedAt: { ...quotedAt, zip: "112" } } }), e, deps);
  assert.equal(calls[0].body.shippingAddress.postalOrZipCode, "112");
  const other = world(PAID, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: { ...PAID_ORDER, quotedAt: { ...quotedAt, country: "GB", zip: "SW1" } } }), other.e, other.deps);
  assert.equal(other.calls[0].body.shippingAddress.postalOrZipCode, "11201");
});

// MARK: The review's cases

test("a charge that went unanswered and was declined lets the order go at once", async () => {
  const { e, c, deps } = world({
    ...PAID,
    "stripe:/payment_intents": () => { throw new TypeError("network connection lost"); },
    "stripe:/payment_intents/search": { data: [{ id: "pi_7", status: "requires_payment_method" }] },
    "stripe:/payment_intents/pi_7": { id: "pi_7", status: "requires_payment_method" },
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  const start = c.t;
  assert.equal(await settle(e, c), "new");
  assert.ok(c.t - start < 10 * 60_000);
});

test("Prodigi busy or in conflict when placing is tried again, never refunded", async () => {
  for (const status of [401, 403, 408, 409, 429]) {
    let busy = true;
    const { e, c, calls, deps } = world({
      ...PAID, "/orders": () => (busy ? (busy = false, new Response("{}", { status })) : new Response(JSON.stringify(PLACED), { status: 202 })),
    }, STRIPE_ENV);
    await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
    assert.equal(await settle(e, c), "accepted", `HTTP ${status}`);
    assert.ok(!calls.some((call) => call.url.endsWith("/refunds")), `HTTP ${status}`);
  }
});

test("a refusal after an unanswered try refunds nothing, and asks Paul to look", async () => {
  let first = true;
  const { e, c, calls, deps } = world({
    ...PAID, "/orders": () => (first ? (first = false, new Response("{}", { status: 502 })) : new Response("{}", { status: 400 })),
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c), "stuck");
  assert.ok(!calls.some((call) => call.url.endsWith("/refunds")));
  assert.match(calls.find((call) => call.url.endsWith("/issues")).body.title, /may or may not/);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("job").recipient, undefined);
});

test("a refused or given-up order keeps no address", async () => {
  for (const status of [400, 503]) {
    const { e, c, deps } = world({ ...PAID, "/orders": () => new Response("{}", { status }) }, STRIPE_ENV);
    await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
    assert.equal(await settle(e, c, 80), status === 400 ? "refused" : "stuck");
    const job = e.PRINT_SHEETS.get(ID).storage.data.get("job");
    assert.equal(job.recipient, undefined);
    assert.equal(job.reference, `sheet-${ID.slice(0, 12)}`);
  }
});

test("the daily check leaves alone an order already alerted, and reads every page", async () => {
  const { e, c, deps } = world({ ...PAID, "/orders": () => new Response("{}", { status: 503 }) }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c, 80), "stuck");
  const day = Math.floor(c.t / 1000) - 7200;
  const OTHER = "fedcba9876543210fedcba9876543210";
  const pages = [
    { has_more: true, data: [{ id: "pi_1", status: "succeeded", created: day, metadata: { sheet: ID } }] },
    { has_more: false, data: [{ id: "pi_2", status: "succeeded", created: day, metadata: { sheet: OTHER } }] },
  ];
  const { calls: checked, fetcher } = prodigi({
    "stripe:/payment_intents": () => new Response(JSON.stringify(pages.shift()), { status: 200 }),
    "stripe:/refunds": { data: [] },
  });
  assert.equal(await reconcilePrints(e, { fetch: fetcher, now: c.now }), 1);
  assert.match(checked.find((call) => call.url.endsWith("/issues")).body.body, /pi_2/);
  assert.match(checked[1].url, /starting_after=pi_1/);
});

test("a declined payment the search shows is read directly before the order is let go", async () => {
  const { e, c, deps } = world({
    ...PAID,
    "stripe:/payment_intents": () => { throw new TypeError("network connection lost"); },
    "stripe:/payment_intents/search": { data: [{ id: "pi_7", status: "requires_payment_method" }] },
    "stripe:/payment_intents/pi_7": { id: "pi_7", status: "succeeded" },
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  const object = e.PRINT_SHEETS.get(ID);
  c.t = object.storage.alarm;
  await object.alarm();
  assert.equal(object.storage.data.get("state"), "charging");
});

test("a refusal after Prodigi said it was busy is refunded as any refusal", async () => {
  let first = true;
  const { e, c, calls, deps } = world({
    ...PAID, "/orders": () => (first ? (first = false, new Response("{}", { status: 429 })) : new Response("{}", { status: 400 })),
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c), "refused");
  assert.ok(calls.some((call) => call.url.endsWith("/refunds")));
});

test("the daily check flags a given-up order whose issue never got filed", async () => {
  const { e, c, deps } = world({
    ...PAID, "/orders": () => new Response("{}", { status: 503 }),
    "github:/repos/owner/feedback/issues": () => new Response("{}", { status: 503 }),
  }, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  assert.equal(await settle(e, c, 80), "stuck");
  const listed = { data: [{ id: "pi_1", status: "succeeded", created: Math.floor(c.t / 1000) - 7200, metadata: { sheet: ID } }] };
  const { fetcher } = prodigi({ "stripe:/payment_intents": listed, "stripe:/refunds": { data: [] } });
  assert.equal(await reconcilePrints(e, { fetch: fetcher, now: c.now }), 1);
});

test("the daily check flags an order whose alarm died in hand, once it is past giving up", async () => {
  const { e, c, deps } = world(PAID, STRIPE_ENV);
  await handlePrint(await orderRequest({ order: PAID_ORDER }), e, deps);
  const object = e.PRINT_SHEETS.get(ID);
  assert.equal(object.storage.data.get("state"), "charged");
  const at = (age) => ({ data: [{ id: "pi_1", status: "succeeded", created: Math.floor(c.t / 1000) - age, metadata: { sheet: ID } }] });
  const young = prodigi({ "stripe:/payment_intents": at(7200), "stripe:/refunds": { data: [] } });
  assert.equal(await reconcilePrints(e, { fetch: young.fetcher, now: c.now }), 0);
  const old = prodigi({ "stripe:/payment_intents": at(50 * 3600), "stripe:/refunds": { data: [] } });
  assert.equal(await reconcilePrints(e, { fetch: old.fetcher, now: c.now }), 1);
});
