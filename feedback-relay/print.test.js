// Tests of One Big Sheet's part of the relay (print.js) against a mocked Prodigi and an in-memory
// Durable Object. `node --test feedback-relay/print.test.js`; CI's `core` job runs it.

import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { test } from "node:test";

import { cleanRecipient, handlePrint, priceFor, PrintSheet, PRODUCTS } from "./print.js";
import { handle } from "./worker.js";

globalThis.crypto ??= webcrypto;

const SANDBOX = "https://api.sandbox.prodigi.com/v4.0";
const KEY = "prodigi-sandbox-SECRET";
const ID = "0123456789abcdef0123456789abcdef";
const TOKEN = "fedcba9876543210fedcba9876543210";
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
          async get(key) { return data.get(key); },
          async put(entries) { for (const [k, v] of Object.entries(entries)) data.set(k, v); },
          async deleteAll() { data.clear(); },
          async setAlarm(at) { storage.alarm = at; },
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

/** A fetch standing in for Prodigi: records each call and answers from `routes`. */
function prodigi(routes) {
  const calls = [];
  const fetcher = async (url, init) => {
    calls.push({ url, init, body: init?.body ? JSON.parse(init.body) : undefined });
    const path = url.slice(SANDBOX.length);
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

async function orderRequest({ sheet = PDF, order = { product: "paper-18x24", recipient: RECIPIENT } } = {}) {
  const form = new FormData();
  if (sheet) form.append("sheet", new Blob([sheet], { type: "application/pdf" }), "sheet.pdf");
  if (order) form.append("order", typeof order === "string" ? order : JSON.stringify(order));
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
  const ids = [ID, TOKEN];
  const { calls, fetcher } = prodigi({ "/orders": PLACED });
  const e = env();
  const answer = await handlePrint(await orderRequest(), e, { fetch: fetcher, randomHex: () => ids.shift() });
  assert.equal(answer.status, 201);
  assert.deepEqual(await answer.json(), { ok: true, order: "ord_123456", sandbox: true });

  const sent = calls[0].body;
  assert.equal(calls[0].url, `${SANDBOX}/orders`);
  assert.equal(sent.items[0].sku, "GLOBAL-FAP-18x24");
  assert.equal(sent.items[0].copies, 1);
  const url = sent.items[0].assets[0].url;
  assert.equal(url, `https://relay.example/v1/print/sheets/${ID}/${TOKEN}.pdf`);
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
  const ids = [ID, TOKEN];
  const { fetcher } = prodigi({ "/orders": PLACED });
  await handlePrint(await orderRequest(), e, { fetch: fetcher, randomHex: () => ids.shift() });
  const wrong = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${"0".repeat(32)}.pdf`), e);
  assert.equal(wrong.status, 404);
  const malformed = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/../x.pdf`), e);
  assert.equal(malformed.status, 404);
  await e.PRINT_SHEETS.get(ID).alarm();
  const gone = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${TOKEN}.pdf`), e);
  assert.equal(gone.status, 404);
});

test("a large sheet is kept in chunks and comes back whole", async () => {
  const big = new Uint8Array(2.5 * 1024 * 1024);
  big.set(new TextEncoder().encode("%PDF-"));
  for (let i = 5; i < big.length; i++) big[i] = i % 251;
  const e = env();
  const ids = [ID, TOKEN];
  const { fetcher } = prodigi({ "/orders": PLACED });
  assert.equal((await handlePrint(await orderRequest({ sheet: big }), e, { fetch: fetcher, randomHex: () => ids.shift() })).status, 201);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.get("chunks"), 3);
  const fetched = await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${TOKEN}.pdf`), e);
  assert.deepEqual(new Uint8Array(await fetched.arrayBuffer()), big);
});

test("an order Prodigi refuses leaves no sheet behind", async () => {
  const e = env();
  const ids = [ID, TOKEN];
  const { fetcher } = prodigi({ "/orders": () => new Response('{"outcome":"ValidationFailed"}', { status: 400 }) });
  assert.equal((await handlePrint(await orderRequest(), e, { fetch: fetcher, randomHex: () => ids.shift() })).status, 502);
  assert.equal(e.PRINT_SHEETS.get(ID).storage.data.size, 0);
});

test("an order without a PDF, with a bad recipient or an unknown product is refused before Prodigi", async () => {
  const { calls, fetcher } = prodigi({ "/orders": PLACED });
  const cases = [
    [{ sheet: new TextEncoder().encode("\x89PNG....") }, 415],
    [{ sheet: null }, 400],
    [{ order: null }, 400],
    [{ order: "{" }, 400],
    [{ order: { product: "mug", recipient: RECIPIENT } }, 400],
    [{ order: { product: "paper-18x24", recipient: { ...RECIPIENT, email: "nope" } } }, 400],
    [{ order: { product: "paper-18x24", recipient: { ...RECIPIENT, zip: "" } } }, 400],
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
  assert.equal((await handle(new Request(`https://relay.example/v1/print/sheets/${ID}/${TOKEN}.pdf`, { method: "POST" }), env())).status, 405);
});
