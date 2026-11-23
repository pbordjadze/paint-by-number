// Tests of One Big Sheet's part of the relay (print.js) against a mocked Prodigi and an in-memory
// Durable Object. `node --test feedback-relay/print.test.js`; CI's `core` job runs it.

import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { webcrypto } from "node:crypto";
import { test } from "node:test";

import { cleanPayment, cleanRecipient, handlePrint, minorUnits, priceFor, PrintSheet, PRODUCTS } from "./print.js";
import { handle } from "./worker.js";

globalThis.crypto ??= webcrypto;

const SANDBOX = "https://api.sandbox.prodigi.com/v4.0";
const STRIPE = "https://api.stripe.com/v1";
const KEY = "prodigi-sandbox-SECRET";
const ID = "0123456789abcdef0123456789abcdef";
const PDF = new TextEncoder().encode("%PDF-1.7\n%stand-in for a sheet\n");
const RECIPIENT = {
  name: "Ada Painter", email: "ada@example.com", line1: "1 Moon Lane", city: "Brooklyn", state: "NY", zip: "11201", country: "US",
};

// MARK: Fakes

/** A Durable Object namespace holding PrintSheets in memory; alarms are recorded, rung by hand. */
function sheetsNamespace() {
  const objects = new Map();
  return {
    objects,
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
          async deleteAll() { data.clear(); },
          async setAlarm(at) { storage.alarm = at; },
          async deleteAlarm() { storage.alarm = null; },
          data,
        };
        const sheet = new PrintSheet({ storage });
        // As a stub does: the call becomes a Request.
        objects.set(id, { storage, alarm: () => sheet.alarm(), fetch: (url, init) => sheet.fetch(new Request(url, init)) });
      }
      return objects.get(id);
    },
  };
}

/** A fetch standing in for Prodigi (and Stripe): records each call and answers from `routes`. */
function prodigi(routes) {
  const calls = [];
  const fetcher = async (url, init) => {
    const stripe = url.startsWith(STRIPE);
    calls.push({ url, init, body: init?.body ? (stripe ? Object.fromEntries(new URLSearchParams(init.body)) : JSON.parse(init.body)) : undefined });
    const path = stripe ? `stripe:${url.slice(STRIPE.length)}` : url.slice(SANDBOX.length);
    const answer = routes[path];
    if (!answer) return new Response("not found", { status: 404 });
    return typeof answer === "function" ? answer() : new Response(JSON.stringify(answer), { status: 200 });
  };
  return { calls, fetcher };
}

const QUOTE = {
  outcome: "Created",
  quotes: [{
    shipmentMethod: "Standard",
    costSummary: { items: { amount: "14.00", currency: "USD" }, shipping: { amount: "9.29", currency: "USD" }, totalCost: { amount: "23.29", currency: "USD" } },
  }],
};
const PLACED = { outcome: "Created", order: { id: "ord_123456", status: { stage: "InProgress" } } };

function env(overrides = {}) {
  return { PRODIGI_API: SANDBOX, PRODIGI_API_KEY: KEY, MARKUP: "0.4", PRINT_SHEETS: sheetsNamespace(), ...overrides };
}

function quoteRequest(body, headers = {}) {
  const text = typeof body === "string" ? body : JSON.stringify(body);
  return new Request("https://relay.example/v1/print/quotes", {
    method: "POST",
    headers: { "content-type": "application/json", "content-length": String(text.length), ...headers },
    body: text,
  });
}

const ORDER = { key: ID, product: "paper-18x24", recipient: RECIPIENT };

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
  const { calls, fetcher } = prodigi({ "/quotes": QUOTE });
  const answer = await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }), env(), { fetch: fetcher });
  assert.equal(answer.status, 200);
  assert.deepEqual(await answer.json(), {
    product: "paper-18x24", currency: "USD", price: "33.00", sandbox: { cost: "23.29", cut: "9.71" },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${SANDBOX}/quotes`);
  assert.equal(calls[0].init.headers["x-api-key"], KEY);
  assert.deepEqual(calls[0].body.items[0].sku, PRODUCTS["paper-18x24"]);
  assert.equal(calls[0].body.destinationCountryCode, "US");
});

test("a quote for an unknown product or a malformed country is refused before Prodigi", async () => {
  const { calls, fetcher } = prodigi({ "/quotes": QUOTE });
  for (const body of [{ product: "mug", country: "US" }, { product: "paper-18x24", country: "usa" }, { product: "paper-18x24" }, "not json"]) {
    const answer = await handlePrint(quoteRequest(body), env(), { fetch: fetcher });
    assert.equal(answer.status, 400, JSON.stringify(body));
  }
  assert.equal(calls.length, 0);
});

test("a quote that isn't JSON, or too large, is refused", async () => {
  const wrongType = await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }, { "content-type": "text/plain" }), env());
  assert.equal(wrongType.status, 415);
  const big = await handlePrint(quoteRequest({ product: "paper-18x24", country: "US", pad: "x".repeat(2000) }), env());
  assert.equal(big.status, 413);
});

test("Prodigi refusing, or answering without a total, is a 502", async () => {
  const refused = prodigi({ "/quotes": () => new Response("{}", { status: 400 }) });
  assert.equal((await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }), env(), { fetch: refused.fetcher })).status, 502);
  const empty = prodigi({ "/quotes": { outcome: "Created", quotes: [] } });
  assert.equal((await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }), env(), { fetch: empty.fetcher })).status, 502);
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
  const { calls, fetcher } = prodigi({ "/quotes": QUOTE, "/orders": PLACED });
  const live = env({ PRODIGI_API: "https://api.prodigi.com/v4.0" });
  assert.equal((await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }), live, { fetch: fetcher })).status, 503);
  assert.equal((await handlePrint(await orderRequest(), live, { fetch: fetcher })).status, 503);
  assert.equal(calls.length, 0);
});

test("without its key or storage the relay says it is misconfigured", async () => {
  for (const missing of ["PRODIGI_API_KEY", "PRODIGI_API", "PRINT_SHEETS"]) {
    const answer = await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }), env({ [missing]: undefined }));
    assert.equal(answer.status, 500, missing);
  }
});

test("a flood is braked", async () => {
  const limiter = { limit: async () => ({ success: false }) };
  const answer = await handlePrint(quoteRequest({ product: "paper-18x24", country: "US" }), env({ PRINT_LIMITER: limiter }));
  assert.equal(answer.status, 429);
});

// MARK: Orders

test("an order keeps the sheet for the printer, places the order with its URL, and Prodigi can fetch it", async () => {
    const { calls, fetcher } = prodigi({ "/orders": PLACED });
  const e = env();
  const answer = await handlePrint(await orderRequest(), e, { fetch: fetcher });
  assert.equal(answer.status, 201);
  assert.deepEqual(await answer.json(), { ok: true, order: "ord_123456", sandbox: true, paid: false });

  const sent = calls[0].body;
  assert.equal(calls[0].url, `${SANDBOX}/orders`);
  assert.equal(sent.items[0].sku, "GLOBAL-FAP-18x24");
  assert.equal(sent.items[0].copies, 1);
  const url = sent.items[0].assets[0].url;
  const token = e.PRINT_SHEETS.get(ID).storage.data.get("token");
  assert.match(token, /^[0-9a-f]{32}$/);
  assert.equal(url, `https://relay.example/v1/print/sheets/${ID}/${token}.pdf`);
  assert.equal(sent.idempotencyKey, ID);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("state"), "placed");
  assert.equal(sent.recipient.name, "Ada Painter");
  assert.equal(sent.recipient.address.postalOrZipCode, "11201");
  assert.equal(sent.recipient.address.countryCode, "US");

  // The printer's fetch, through the whole worker.
  const fetched = await handle(new Request(url), e);
  assert.equal(fetched.status, 200);
  assert.equal(fetched.headers.get("content-type"), "application/pdf");
  assert.deepEqual(new Uint8Array(await fetched.arrayBuffer()), PDF);
  // Kept two weeks.
  const storage = e.PRINT_SHEETS.get(ID).storage;
  assert.ok(storage.alarm > Date.now() + 13 * 24 * 3600 * 1000);
});

test("a kept sheet answers only its own token, and goes when its alarm rings", async () => {
  const e = env();
    const { fetcher } = prodigi({ "/orders": PLACED });
  await handlePrint(await orderRequest(), e, { fetch: fetcher });
  const wrong = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${"0".repeat(32)}.pdf`), e);
  assert.equal(wrong.status, 404);
  const malformed = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/../x.pdf`), e);
  assert.equal(malformed.status, 404);
  const token = e.PRINT_SHEETS.get(ID).storage.data.get("token");
  assert.equal((await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${token}.pdf`), e)).status, 200);
  await e.PRINT_SHEETS.get(ID).alarm();
  const gone = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${token}.pdf`), e);
  assert.equal(gone.status, 404);
});

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

test("an order Prodigi refuses leaves no sheet behind", async () => {
  const e = env();
    const { fetcher } = prodigi({ "/orders": () => new Response('{"outcome":"ValidationFailed"}', { status: 400 }) });
  assert.equal((await handlePrint(await orderRequest(), e, { fetch: fetcher })).status, 502);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.size, 0);
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

test("with Stripe, an order is charged the agreed price through Apple Pay before it is placed", async () => {
    const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(answer.status, 201);
  assert.deepEqual(await answer.json(), { ok: true, order: "ord_123456", sandbox: true, paid: true });
  assert.deepEqual(calls.map((c) => c.url), [`${SANDBOX}/quotes`, `${STRIPE}/tokens`, `${STRIPE}/payment_intents`, `${SANDBOX}/orders`]);
  assert.equal(calls[1].init.headers.authorization, "Bearer sk_test_SECRET");
  assert.equal(calls[1].body.pk_token, '{"version":"EC_v1","data":"…"}');
  assert.equal(calls[1].body.pk_token_payment_network, "Visa");
  assert.equal(calls[2].body.amount, "3300");
  assert.equal(calls[2].body.currency, "usd");
  assert.equal(calls[2].body["payment_method_data[card][token]"], "tok_1");
  assert.equal(calls[2].body.confirm, "true");
});

test("with Stripe, an order without a payment, or at a price that moved, is not placed", async () => {
  const { calls, fetcher } = prodigi({ "/quotes": QUOTE, "/orders": PLACED });
  const unpaid = await handlePrint(await orderRequest(), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(unpaid.status, 402);
  const moved = await handlePrint(await orderRequest({ order: { ...PAID_ORDER, price: "30.00" } }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(moved.status, 409);
  assert.ok(!calls.some((c) => c.url.endsWith("/orders") || c.url.startsWith(STRIPE)));
});

test("a declined card is a 402 and places nothing", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": PLACED, "stripe:/tokens": { id: "tok_1" },
    "stripe:/payment_intents": () => new Response('{"error":{"type":"card_error","code":"card_declined"}}', { status: 402 }),
  });
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(answer.status, 402);
  assert.ok(!calls.some((c) => c.url === `${SANDBOX}/orders`));
});

test("a paid order Prodigi refuses is refunded", async () => {
    const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": () => new Response("{}", { status: 400 }),
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" }, "stripe:/refunds": { id: "re_1" },
  });
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(answer.status, 502);
  const refund = calls.find((c) => c.url === `${STRIPE}/refunds`);
  assert.equal(refund?.body.payment_intent, "pi_1");
  assert.equal(refund?.init.headers["idempotency-key"], `${ID}-refund`);
});

test("a live Stripe key is never used against the sandbox printer", async () => {
  const { calls, fetcher } = prodigi({ "/quotes": QUOTE, "/orders": PLACED });
  const answer = await handlePrint(await orderRequest({ order: PAID_ORDER }), env({ STRIPE_SECRET_KEY: "sk_live_REAL" }), { fetch: fetcher });
  assert.equal(answer.status, 503);
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
    "/quotes": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  const payment = { ...PAYMENT, data: Buffer.from("x".repeat(6000)).toString("base64") };
  const answer = await handlePrint(await orderRequest({ order: { ...PAID_ORDER, payment } }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(answer.status, 201);
});

test("Stripe's calls carry the order's idempotency keys", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  await handlePrint(await orderRequest({ order: PAID_ORDER }), env(STRIPE_ENV), { fetch: fetcher });
  assert.equal(calls[1].init.headers["idempotency-key"], `${ID}-token`);
  assert.equal(calls[2].init.headers["idempotency-key"], `${ID}-intent`);
  assert.equal(calls[2].body["metadata[sheet]"], ID);
});

test("an order placed already is answered again, with nothing charged or placed twice", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": PLACED,
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  const e = env(STRIPE_ENV);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher })).status, 201);
  const made = calls.length;
  const again = await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher });
  assert.equal(again.status, 201);
  assert.deepEqual(await again.json(), { ok: true, order: "ord_123456", sandbox: true, paid: true });
  assert.equal(calls.length, made);
});

test("Prodigi failing in a way that may have placed it refunds nothing, keeps the sheet, and blocks a second try", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": () => new Response("{}", { status: 503 }),
    "stripe:/tokens": { id: "tok_1" }, "stripe:/payment_intents": { id: "pi_1", status: "succeeded" },
  });
  const e = env(STRIPE_ENV);
  const first = await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher });
  assert.equal(first.status, 202);
  assert.deepEqual(await first.json(), { ok: false, pending: true });
  assert.ok(!calls.some((c) => c.url === `${STRIPE}/refunds`));
  const data = e.PRINT_SHEETS.get(ID).storage.data;
  assert.equal(data.get("state"), "placing");
  assert.equal(data.get("charge"), "pi_1");
  const made = calls.length;
  const again = await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher });
  assert.equal(again.status, 202);
  assert.deepEqual(await again.json(), { ok: false, pending: true });
  assert.equal(calls.length, made);
});

test("Stripe not answering leaves the order charging, never charged twice", async () => {
  const { calls, fetcher } = prodigi({
    "/quotes": QUOTE, "/orders": PLACED, "stripe:/tokens": { id: "tok_1" },
    "stripe:/payment_intents": () => { throw new TypeError("network connection lost"); },
  });
  const e = env(STRIPE_ENV);
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher })).status, 202);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("state"), "charging");
  assert.ok(!calls.some((c) => c.url === `${SANDBOX}/orders`));
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher })).status, 202);
});

test("an order that surely failed can be tried again under its key", async () => {
  let refuse = true;
  const { fetcher } = prodigi({
    "/orders": () => (refuse ? new Response("{}", { status: 400 }) : new Response(JSON.stringify(PLACED), { status: 200 })),
  });
  const e = env();
  assert.equal((await handlePrint(await orderRequest(), e, { fetch: fetcher })).status, 502);
  refuse = false;
  assert.equal((await handlePrint(await orderRequest(), e, { fetch: fetcher })).status, 201);
});

test("the sheet's store failing charges nothing", async () => {
  const { calls, fetcher } = prodigi({ "/quotes": QUOTE, "/orders": PLACED });
  const e = env(STRIPE_ENV);
  e.PRINT_SHEETS = { idFromName: (n) => n, get: () => ({ fetch: async () => { throw new Error("overloaded"); } }) };
  assert.equal((await handlePrint(await orderRequest({ order: PAID_ORDER }), e, { fetch: fetcher })).status, 502);
  assert.equal(calls.length, 0);
});
