// One Big Sheet (SideStore and Debug builds; painting-company row 380): the relay sends a template
// the painter chose to print to Prodigi's print API, which prints it as one full-size sheet and
// mails it. worker.js routes /v1/print/ here; tested by `node --test feedback-relay/print.test.js`.
//
//   POST /v1/print/quotes          {"product": "<id>", "country": "US"[, "city", "state", "zip"]},
//                                  application/json, at most 1 KB; the city, state and postal code
//                                  are the Apple Pay sheet's, once it shares them. 200 {"product",
//                                  "currency", "price"[, "sandbox": {"cost", "cut"}]}: the price the
//                                  painter pays there, shipping and Prodigi's tax included (its cost
//                                  with MARKUP, rounded up to a whole unit); "sandbox" says, while
//                                  the relay talks to the sandbox, what the order costs and what is
//                                  kept. The same quote is kept ten minutes (`priceOf`).
//   PUT  /v1/print/sheets/<key>    application/pdf, at most 25 MB: the order's one-page sheet,
//                                  kept under the order's key before it is paid for, so the Apple
//                                  Pay sheet waits on the charge alone. 200 {"ok": true}. A sheet
//                                  sent again replaces it until the order is taken.
//   POST /v1/print/orders          application/json, at most 32 KB: {"key", "product", "recipient":
//                                  {"name", "email", "line1", "line2"?, "city", "state"?, "zip",
//                                  "country"}[, "price", "currency", "payment": {"data", "network",
//                                  "transactionId", "instrument"}, "quotedAt": {"country", "city",
//                                  "state", "zip"}]}; 412 when no sheet is kept under
//                                  the key. Or, from an older app, multipart/form-data with `sheet`
//                                  (the PDF) and `order` (that JSON, a field or a file part). `key`
//                                  (32 hex digits) is the app's for this order, the same on every
//                                  try: an order is charged and placed once. With STRIPE_SECRET_KEY
//                                  set the order is paid first: the price is quoted again at the
//                                  recipient's city, state and postal code and must be the one the
//                                  painter agreed to (409 if it moved), and the Apple Pay payment
//                                  (PKPaymentToken's paymentData, base64) is charged through Stripe
//                                  (402 declined or missing). Then the order is the relay's: 201
//                                  {"ok": true, "order": "sheet-<first 12 of key>", "sandbox",
//                                  "paid"}, also for any later try of it, and its Durable Object's
//                                  alarm places it with the sheet's URL (below), checks Prodigi took
//                                  it and refunds the payment if not, filing an issue in
//                                  FEEDBACK_REPO for anything that needs Paul. 202 {"ok": false,
//                                  "pending": true} while a try of it is under way or Stripe gave
//                                  no clear answer (the alarm asks Stripe); 410 {"ok": false,
//                                  "refused": true, "refunded"} for one Prodigi refused.
//                                  451 {"ok": false, "declined": true}, nothing charged, for a
//                                  sheet the check (below) won't print.
//   GET  /v1/print/sheets/<id>/<token>.pdf
//                                  the kept sheet, for Prodigi's printer: 404 for anything else.
//   GET, POST /v1/print/review/<id>/<token>
//                                  Paul's page for an order the check held: the sheet, the reason,
//                                  and Print it or Refund it (a form, so a link preview can't act).
// The check (with ANTHROPIC_API_KEY set; `checkSheet`): a kept sheet is shown to Claude (CHECK_MODEL,
// by the sheet's URL, never its photo, which the relay never has) as soon as it is kept, so its
// answer is usually in before the painter has paid. A sheet that blatantly can't be printed (a
// famous character or logo, someone else's artwork in copyright, sexual or illegal content) is
// declined before the charge, or refunded should the answer come after it; one it isn't sure
// of is held, an issue filed with the review page's link, and refunded if Paul hasn't decided
// within HOLD_MS. No answer, or more checks today than CHECK_DAILY_LIMIT, holds it too. The painter
// is told only that the picture can't be printed.
// Once a day (worker.js's scheduled, wrangler.toml's cron) `reconcilePrints` matches Stripe's
// payments for sheets against the orders Prodigi accepted, and files an issue for one that isn't.
//
// Failures are a bare status (the log has the detail): 400 a malformed body or an unknown product,
// 404 another path, 405 another method, 411 no Content-Length, 413 too large, 415 not JSON or
// multipart, or a sheet that is no PDF, 429 over the rate limit (PRINT_LIMITER, counted at each
// Cloudflare location apart), 500 misconfigured, 502 Prodigi or Stripe refused, 503 live printing
// or charging, which this relay doesn't do (below).
//
// Only the sandbox. PRODIGI_API must be Prodigi's v5 API (https://api.prodigi.com/v5) and its key the
// sandbox dashboard's (https://sandbox-beta-dashboard.pwinty.com), sent as `sandbox_<key>`, which
// prints nothing and charges nothing, and STRIPE_SECRET_KEY, when set, Stripe's test mode
// (sk_test_, or a restricted rk_test_ key with Tokens, PaymentIntents and Refunds write), so no
// real card is charged for a print that never comes. Going live is Paul's word,
// with both keys live and payment required: a live print service never takes an unpaid order.
//
// Privacy: the photo never comes here, only the printed sheet (lines traced from it, numbers, the
// key) and the address it goes to. The sheet lives in its own Durable Object (PrintSheet,
// SQLite-backed, named by the order's random key) under a random token, and deletes itself
// SHEET_DAYS after it was kept, by an alarm; the sheet's URL goes to Anthropic for the check; the name, email and address go to Prodigi (and with a
// payment to Stripe, for its receipt and shipping record), and are kept in the order's object only
// until Prodigi has accepted the order (or two days, when it is given up on). Issues name no one.
//
// The print service is one object (`prodigi` below; PRINT_PROVIDER names another), so it can be
// replaced without touching the rest. Secrets PRODIGI_API_KEY (Prodigi's sandbox dashboard › API; never a live_ key) and, optional,
// STRIPE_SECRET_KEY (Stripe's dashboard › Developers › API keys; the test key) and
// ANTHROPIC_API_KEY (the check). Variables PRODIGI_API, MARKUP and, optional, CHECK_MODEL and
// CHECK_DAILY_LIMIT (wrangler.toml).

import { Buffer } from "node:buffer";

const PREFIX = "/v1/print/";
const QUOTES = "/v1/print/quotes";
const ORDERS = "/v1/print/orders";
const SHEETS = "/v1/print/sheets/";
// Prodigi's v5 API takes one URL for its sandbox and live; the key's prefix picks which, and
// this relay only ever sends a sandbox one (`prodigiKey`).
const SANDBOX = "https://api.prodigi.com/v5";
const STRIPE = "https://api.stripe.com/v1";
const MAX_QUOTE = 1024;
// An Apple Pay token (a PKCS#7 signature with its certificates, base64) is several KB.
const MAX_ORDER_JSON = 32 * 1024;
const MAX_ORDER = 25 * 1024 * 1024;
const MAX_FIELD = 200;
const CHUNK = 1024 * 1024;
const SHEET_DAYS = 14;
/** How long a try holds an order still "new" (pricing it) before another may take it on. */
const CLAIM_MS = 120_000;
const SHIPPING = "standard";
const PDF = [0x25, 0x50, 0x44, 0x46, 0x2d];
const REVIEW = "/v1/print/review/";
const HEX = /^[0-9a-f]{32}$/;
const COUNTRY = /^[A-Z]{2}$/;

// MARK: The print service

/**
 * A print service is one object (PRINT_PROVIDER picks it, Prodigi by default), so another (Gelato,
 * say) is a second object of the same shape and nothing else here changes:
 *   products              the app's product ids → the service's own product codes
 *   configured(env)       whether its secrets and settings are there
 *   isSandbox(env)        whether it is talking to its test system, which prints nothing
 *   cost(env, deps, code, {country, city, state, zip})   → {cost, currency}: one sheet sent
 *                         there, shipping included (city, state and zip may be "")
 *   place(env, deps, {reference, key, code, recipient, sheetUrl})   → the service's order id; the
 *                         same key placed again must not make a second order, and an error that
 *                         leaves it unknown whether one was made carries `uncertain`
 *   status(env, deps, id) → {status, issues}: the service's word on the order, in Prodigi's terms
 *                         (`ACCEPTED`; "cancelled", "failed", or "draft" with "fulfilment_issue"
 *                         refused it; "on_hold" needs Paul)
 */
export const prodigi = {
  name: "Prodigi",
  // Rolled canvas, 400 gsm cotton, for acrylic, and cold press watercolour paper, 315 gsm cotton
  // rag, for watercolor (painting-company row 380), the app's `BigSheetProduct`. Each code was
  // quoted by Prodigi's sandbox before it was offered here.
  products: {
    "canvas-16x24": "GLOBAL-CAN-ROL-SC-16X24",
    "canvas-24x36": "GLOBAL-CAN-ROL-SC-24X36",
    "watercolor-18x24": "ART-FAP-CPWP-18X24",
    "watercolor-24x36": "ART-FAP-CPWP-24X36",
  },

  configured: (env) => Boolean(env.PRODIGI_API_KEY && env.PRODIGI_API),

  isSandbox: (env) => env.PRODIGI_API === SANDBOX && prodigiKey(env) !== null,

  async cost(env, deps, code, place) {
    // A quote wants a whole address: the city, state and postal code where the painter's Apple Pay
    // sheet has shared them (the order's price is the same, from its own), a stand-in street, and
    // a stand-in postcode in the country before that. Prodigi's total carries the tax it charges.
    const answer = await prodigiCall(env, deps, "POST", "/quotes/order", {
      shippingMethod: SHIPPING,
      shippingAddress: {
        line1: "1 Main Street",
        townOrCity: place.city || "City",
        ...(place.state ? { stateOrCounty: place.state } : {}),
        postalOrZipCode: place.zip || (POSTCODES[place.country] ?? "1000"),
        countryCode: place.country,
      },
      items: [{ catalogueVariantId: code, quantity: 1 }],
    });
    const total = answer?.data?.total;
    const cost = Number(total?.amount);
    if (!Number.isFinite(cost) || cost <= 0 || typeof total?.currency !== "string") {
      throw new Error("Prodigi's quote had no total");
    }
    return { cost, currency: total.currency };
  },

  async place(env, deps, { reference, key, code, recipient, sheetUrl }) {
    // An order made again under the same idempotency key is answered with the one already made.
    const placed = await prodigiCall(env, deps, "POST", "/orders", {
      merchantReference: reference,
      shippingMethod: SHIPPING,
      submit: true,
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
        quantity: 1,
        sizing: "fitPrintArea",
        assets: [{ printArea: "default", url: sheetUrl }],
      }],
    }, { "idempotency-key": key });
    const id = placed?.data?.id;
    if (typeof id !== "string") throw Object.assign(new Error("Prodigi's answer had no order id"), { uncertain: true });
    return id;
  },

  async status(env, deps, id) {
    // Accepted with 202 isn't taken: the submission runs after, and may refuse it.
    const answer = await prodigiCall(env, deps, "GET", `/orders/${encodeURIComponent(id)}`);
    const status = answer?.data?.status;
    if (typeof status !== "string") throw Object.assign(new Error("Prodigi's order had no status"), { uncertain: true });
    const issues = (answer?.data?.issues ?? []).map((issue) => String(issue?.code ?? "")).filter(Boolean);
    return { status, issues };
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
  if (url.pathname.startsWith(REVIEW)) return review(request, env, url.pathname.slice(REVIEW.length));
  const upload = url.pathname.startsWith(SHEETS) ? /^([0-9a-f]{32})$/.exec(url.pathname.slice(SHEETS.length)) : null;
  if (url.pathname.startsWith(SHEETS) && !upload) {
    if (request.method !== "GET" && request.method !== "HEAD") return bare(405, { allow: "GET" });
    return sheet(url.pathname.slice(SHEETS.length), env);
  }
  if (upload) {
    if (request.method !== "PUT") return bare(405, { allow: "PUT" });
  } else if (url.pathname !== QUOTES && url.pathname !== ORDERS) {
    return bare(404);
  } else if (request.method !== "POST") {
    return bare(405, { allow: "POST" });
  }
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
  if (upload) return putSheet(request, env, upload[1]);
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
  const place = { country: body.country, city: cleanField(body.city, false), state: cleanField(body.state, false), zip: cleanField(body.zip, false) };
  if (place.city === null || place.state === null || place.zip === null) return bare(400);
  let priced;
  try {
    priced = await priceOf(env, deps, provider, code, place);
  } catch (error) {
    log("Quoting failed", error);
    return bare(502);
  }
  return json(200, {
    product: body.product, currency: priced.currency, price: money(priced.price),
    sandbox: { cost: money(priced.cost), cut: money(priced.price - priced.cost) },
  });
}

/**
 * The service's cost of one sheet sent to `place`, shipping included, and the painter's price.
 * The same quote is kept QUOTE_MS in this isolate (best effort: a quote and its order, a minute
 * apart, ask Prodigi once). Tests that hand in their own fetch keep none, unless they pass a cache.
 */
async function priceOf(env, deps, provider, code, place) {
  const cache = deps.quoteCache ?? (deps.fetch ? null : QUOTE_CACHE);
  const now = (deps.now ?? Date.now)();
  const name = JSON.stringify([provider.name, code, place.country, place.city, place.state, place.zip]);
  let quoted = cache?.get(name);
  if (!quoted || now - quoted.at > QUOTE_MS) {
    quoted = { ...(await provider.cost(env, deps, code, place)), at: now };
    if (cache) {
      if (cache.size >= 500) cache.clear();
      cache.set(name, quoted);
    }
  }
  return { cost: quoted.cost, currency: quoted.currency, price: priceFor(quoted.cost, env.MARKUP) };
}

const QUOTE_MS = 10 * 60_000;
const QUOTE_CACHE = new Map();

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

/**
 * Takes an order: the sheet kept (with it, from an older app, or by PUT before), the price checked
 * at the address it goes to, the payment charged, and the order handed to its own Durable Object,
 * whose alarm places it with the print service, checks the service took it and refunds the payment
 * if it didn't (`advance`). The painter waits on the charge alone: nothing the phone does after it
 * (a lost signal, the app put away) can leave a payment with no print, or no refund.
 */
async function order(request, env, deps, provider) {
  const length = request.headers.get("content-length");
  if (length === null || !/^\d+$/.test(length)) return bare(411);
  if (Number(length) > MAX_ORDER) return bare(413);
  const type = request.headers.get("content-type") ?? "";
  let orderText, file = null;
  if (/^application\/json\b/i.test(type)) {
    if (Number(length) > MAX_ORDER_JSON) return bare(413);
    orderText = await readCapped(request, MAX_ORDER_JSON);
    if (orderText === null) return bare(413);
  } else if (/^multipart\/form-data\s*;/i.test(type)) {
    let form;
    try {
      form = await request.formData();
    } catch {
      return bare(400);
    }
    file = form.get("sheet");
    orderText = await partText(form.get("order"), MAX_ORDER_JSON);
    if (!isBlob(file) || file.size === 0 || orderText === null) return bare(400);
    if (file.size > MAX_ORDER) return bare(413);
    if (!(await startsWith(file, PDF))) return bare(415);
  } else {
    return bare(415);
  }
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
    if (provider.isSandbox(env) && !/^(sk|rk)_test_/.test(env.STRIPE_SECRET_KEY)) {
      log(`STRIPE_SECRET_KEY is live while ${provider.name} is its sandbox`);
      return bare(503);
    }
    payment = cleanPayment(body?.payment);
    if (!payment) return bare(402);
  } else if (!provider.isSandbox(env)) {
    // A real print is never sent unpaid, whatever else is set.
    log(`${provider.name} is live without STRIPE_SECRET_KEY: no order is taken unpaid`);
    return bare(402);
  }

  const stub = sheetStub(env, key);
  if (file && !(await keep(stub, await file.arrayBuffer(), new URL(request.url).origin, key))) return bare(502);
  let begun;
  try {
    const answer = await stub.fetch("https://sheet/begin", { method: "POST" });
    // No sheet kept under the key: the app sends it (PUT) and tries again.
    if (answer.status === 404) return bare(412);
    if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
    begun = await answer.json();
  } catch (error) {
    log("Beginning the order failed", error);
    return bare(502);
  }
  const reference = referenceOf(key);
  if (TAKEN.has(begun.state)) return takenAnswer(env, provider, reference, begun.charge);
  if (begun.state === "refused") return json(410, { ok: false, refused: true, refunded: begun.refunded === true });
  // Only the try holding the order's claim goes on: another try of it under way at once waits.
  const claim = begun.claim;
  if (!claim) {
    log(`Order ${key} is ${begun.state} already (payment ${begun.charge ?? "none"})`);
    return json(202, { ok: false, pending: true });
  }
  // The check's answer, waited for a little while it is under way: a declined sheet costs nothing.
  // One still unanswered goes on, and its object's alarm waits for the answer before placing it.
  const verdict = begun.checking ? await awaitVerdict(stub, deps) : begun.verdict;
  if (verdict === "refuse") {
    await drop(stub, claim);
    return json(451, { ok: false, declined: true });
  }

  const now = (deps.now ?? Date.now)();
  const job = { key, code, recipient, reference, provider: provider.name, origin: new URL(request.url).origin, since: now, tries: 0 };
  if (!payment) {
    // Leaving "new" is the gate: unrecorded, nothing is placed (the claim lapses, a later try takes it).
    if (!(await mark(stub, claim, { state: "queued", job, alarmIn: 0 }))) return json(202, { ok: false, pending: true });
    return takenAnswer(env, provider, reference, null);
  }

  let priced;
  try {
    priced = await priceOf(env, deps, provider, code, quotedPlace(body?.quotedAt, recipient));
  } catch (error) {
    log("Pricing the order failed", error);
    await drop(stub, claim);
    return bare(502);
  }
  // The painter agreed to the price on screen: a price that moved since is asked again.
  if (money(priced.price) !== body.price || priced.currency !== body.currency) {
    await drop(stub, claim);
    return bare(409);
  }
  // The order's object takes it from "charging" on: should this try go away mid charge, its alarm
  // finds out from Stripe whether the payment was taken, and places the order or lets it go.
  if (!(await mark(stub, claim, { state: "charging", job, alarmIn: CHARGE_SETTLE_MS }))) return json(202, { ok: false, pending: true });
  let charge;
  try {
    charge = await chargeApplePay(env, deps, payment, priced, key, recipient);
  } catch (error) {
    if (error?.uncertain) {
      log(`Stripe may have charged order ${key}: its alarm looks it up`, error);
      return json(202, { ok: false, pending: true });
    }
    log("Charging the order failed", error);
    await drop(stub, claim);
    return bare(error?.declined ? 402 : 502);
  }
  // Charged: the object's alarm places it now. Should this mark fail, the alarm set at "charging"
  // finds the payment in Stripe and places it all the same.
  await mark(stub, claim, { state: "charged", charge, alarmIn: 0 });
  return takenAnswer(env, provider, reference, charge);
}

/** States in which the order is the relay's to place: an answer of 201 for any try of it. */
const TAKEN = new Set(["queued", "charged", "held", "placing", "placed", "accepted"]);

/** The order's name with the print service and the painter: what the app shows as its number. */
function referenceOf(key) {
  return `sheet-${key.slice(0, 12)}`;
}

function takenAnswer(env, provider, reference, charge) {
  return json(201, { ok: true, order: reference, sandbox: provider.isSandbox(env), paid: Boolean(charge) });
}

/** Keeps a sheet under its order's key (`keep` of PrintSheet); says whether it did. */
async function keep(stub, bytes, origin, key) {
  try {
    const answer = await stub.fetch("https://sheet/keep", { method: "POST", headers: { "x-days": String(SHEET_DAYS), "x-origin": origin, "x-key": key }, body: bytes });
    if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
    return true;
  } catch (error) {
    log("Keeping the sheet failed", error);
    return false;
  }
}

/** PUT /v1/print/sheets/<key>: the sheet kept before the order, so paying waits on nothing else. */
async function putSheet(request, env, key) {
  const length = request.headers.get("content-length");
  if (length === null || !/^\d+$/.test(length)) return bare(411);
  if (Number(length) > MAX_ORDER) return bare(413);
  if (!/^application\/pdf\b/i.test(request.headers.get("content-type") ?? "")) return bare(415);
  const text = await readBytesCapped(request, MAX_ORDER);
  if (text === null) return bare(413);
  if (text.byteLength < PDF.length || !PDF.every((byte, i) => text[i] === byte)) return bare(415);
  return (await keep(sheetStub(env, key), text, new URL(request.url).origin, key)) ? json(200, { ok: true }) : bare(502);
}

/**
 * Records where an order stands, for the try holding its claim; says whether it did. A failure is
 * logged: past "new" the state before it still keeps every other try out.
 */
async function mark(stub, claim, state) {
  try {
    const answer = await stub.fetch("https://sheet/mark", { method: "POST", headers: { "x-claim": claim }, body: JSON.stringify(state) });
    if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
    return true;
  } catch (error) {
    log(`Recording an order as ${state.state} failed`, error);
    return false;
  }
}

/** Lets go of an order that surely failed (its sheet stays), only for the try holding its claim. */
async function drop(stub, claim) {
  try {
    await stub.fetch("https://sheet/drop", { method: "POST", headers: { "x-claim": claim } });
  } catch (error) {
    log("Dropping an order failed", error);
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
  const field = (name, required) => cleanField(value[name], required);
  const cleaned = {
    name: field("name", true), email: field("email", true), line1: field("line1", true), line2: field("line2", false),
    city: field("city", true), state: field("state", false), zip: field("zip", true), country: field("country", true),
  };
  if (Object.values(cleaned).some((v) => v === null)) return null;
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleaned.email) || !COUNTRY.test(cleaned.country)) return null;
  return cleaned;
}

function cleanField(raw, required) {
  if (raw === undefined || raw === null || raw === "") return required ? null : "";
  if (typeof raw !== "string") return null;
  const text = raw.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  if (text.length > MAX_FIELD || (required && text === "")) return null;
  return text;
}

/**
 * Where the order is priced: where the app was quoted, which Apple Pay's sheet told it before the
 * painter paid (its postal code may be cut short there, so the full one could price differently
 * and turn the painter's price back), when that is in the recipient's country; else the recipient's.
 */
function quotedPlace(value, recipient) {
  if (value && typeof value === "object") {
    const place = { country: recipient.country, city: cleanField(value.city, false), state: cleanField(value.state, false), zip: cleanField(value.zip, false) };
    if (value.country === recipient.country && place.city !== null && place.state !== null && place.zip !== null) return place;
  }
  return placeOf(recipient);
}

/** Where a price is for: the country, and the city, state and postal code where known. */
function placeOf(address) {
  return { country: address.country, city: address.city ?? "", state: address.state ?? "", zip: address.zip ?? "" };
}

// MARK: Placing, checking, refunding (the order's alarm)

/** How long an order stays "charging" before its alarm asks Stripe whether it was paid. */
const CHARGE_SETTLE_MS = 5 * 60_000;
/** How long Stripe is asked about a payment it can't find before the order is let go, unpaid. */
const CHARGE_LOST_MS = 30 * 60_000;
/** How long the alarm keeps at an order before it says so and stops. */
const GIVE_UP_MS = 2 * 24 * 3600_000;
const HOUR = 3600_000;
/** How long a held order waits for Paul's look before it is refunded. */
const HOLD_MS = 24 * HOUR;
const ACCEPTED = new Set(["submitted", "in_production", "partially_shipped", "shipped", "completed", "paused"]);
/** A payment intent's statuses that took no money and never will. */
const UNTAKEN = new Set(["requires_payment_method", "canceled"]);

const ACTIVE = new Set(["charging", "queued", "charged", "held", "placing", "placed"]);

/**
 * One step of an order the relay has taken, by where it stands; answers how long until the next
 * step, or null once it is settled. Every change is stored before the next call goes out, so an
 * alarm cut off midway is taken up again by the next one (each call is idempotent: Stripe's and
 * Prodigi's under the order's keys).
 */
export async function advance(env, deps, storage, standing) {
  const now = (deps.now ?? Date.now)();
  const { state, job, charge, key } = standing;
  const provider = PROVIDERS[job.provider === prodigi.name ? "prodigi" : env.PRINT_PROVIDER ?? "prodigi"] ?? prodigi;
  const facts = { key, reference: job.reference, charge, order: standing.order, state };
  if (now - job.since > GIVE_UP_MS) {
    await alert(env, deps, storage, "stuck", `stopped trying an order still ${state}`, facts,
      "The relay tried this order for two days. Look it up in Prodigi's and Stripe's dashboards and place or refund it by hand (the address is on the Stripe payment's shipping; the relay keeps none).");
    await storage.put({ state: "stuck", job: stripped(job) });
    return null;
  }
  if (!provider.isSandbox(env)) {
    log(`${provider.name} is not its sandbox: order ${key} waits for live printing`);
    return HOUR;
  }

  if (state === "charging") {
    if (now - job.since < CHARGE_SETTLE_MS) return job.since + CHARGE_SETTLE_MS - now;
    const found = await paymentOf(env, deps, key);
    if (found?.status === "succeeded") {
      await storage.put({ state: "charged", charge: found.id });
      return 0;
    }
    // Still settling at Stripe; a declined or cancelled one took nothing.
    if (found && !UNTAKEN.has(found.status)) return 5 * 60_000;
    // Search can lag: the payment itself, read directly, says it took nothing.
    if (found && !UNTAKEN.has((await stripeGet(env, deps, `/payment_intents/${encodeURIComponent(found.id)}`))?.status)) return 5 * 60_000;
    if (!found && now - job.since < CHARGE_LOST_MS) return 5 * 60_000;
    // Nothing taken: the order is the painter's to try again.
    log(`Order ${key} was never charged: let go`);
    await storage.put({ state: "new", claimedAt: 0 });
    await storage.delete?.("job");
    return null;
  }

  if (state === "held") {
    // A decision taken here is recorded first, so a later one on the review page is refused.
    const deadline = (standing.heldAt ?? now) + HOLD_MS;
    if (!standing.review && now >= deadline) await storage.put({ review: "expired" });
    if (standing.review === "release") {
      await storage.put({ state: charge ? "charged" : "queued", released: true });
      return 0;
    }
    if (standing.review === "refuse") {
      return await refuse(env, deps, storage, job, { ...facts, check: standing.verdict?.reason }, "Paul refused the sheet the check held.");
    }
    if (now < deadline) return deadline - now;
    return await refuse(env, deps, storage, job, { ...facts, check: standing.verdict?.reason }, "The check held the sheet and nobody decided within a day.");
  }

  if ((state === "queued" || state === "charged") && !standing.released) {
    // The check first: an order is never placed while it is under way, or against its answer.
    if (standing.check === "due") return 30_000;
    const verdict = standing.verdict;
    if (verdict?.verdict === "refuse") {
      return await refuse(env, deps, storage, job, { ...facts, check: verdict.reason },
        "The check refused the sheet after the order was taken.");
    }
    if (verdict?.verdict === "hold") {
      const reviewToken = standing.reviewToken ?? randomHex();
      await storage.put({ state: "held", heldAt: now, reviewToken });
      await alert(env, deps, storage, "held", "a sheet waits for your look", { ...facts, state: "held", check: verdict.reason },
        `The check wasn't sure this sheet can be printed. Look at it and decide: ${job.origin}${REVIEW}${key}/${reviewToken} (the painter has ${charge ? "paid" : "not paid; a sandbox order"}). Undecided, it is refunded a day from now.`);
      return HOLD_MS;
    }
  }

  if (state === "queued" || state === "charged" || state === "placing") {
    await storage.put({ state: "placing" });
    try {
      const sheetUrl = `${job.origin}${SHEETS}${key}/${standing.token}.pdf`;
      const id = await provider.place(env, deps, { reference: job.reference, key, code: job.code, recipient: job.recipient, sheetUrl });
      await storage.put({ state: "placed", order: id, job: { ...job, tries: 0, unanswered: false } });
      return 20_000;
    } catch (error) {
      if (error?.uncertain) {
        // Only no answer, or a 5xx, leaves it open whether Prodigi made the order.
        const unanswered = job.unanswered || !error.status || error.status >= 500;
        return retry(storage, { ...job, unanswered }, `Placing order ${key}`, error);
      }
      if (job.unanswered) {
        // An earlier try may have placed it: refunding could give back an order being printed.
        await alert(env, deps, storage, "unsure", "an order may or may not be placed", facts,
          `${provider.name} refused the order (${error.message}) after an earlier try went unanswered. Look it up in its dashboard by its reference: if it isn't there, refund the payment in Stripe.`);
        await storage.put({ state: "stuck", job: stripped(job) });
        return null;
      }
      log(`${provider.name} refused order ${key}`, error);
      return await refuse(env, deps, storage, job, facts, `${provider.name} refused the order when it was placed (${error.message}).`);
    }
  }

  if (state === "placed") {
    let status;
    try {
      status = await provider.status(env, deps, standing.order);
    } catch (error) {
      // A new order may not be readable for a few seconds.
      if (error?.uncertain || error?.status === 404) return retry(storage, job, `Checking order ${key}`, error);
      throw error;
    }
    if (ACCEPTED.has(status.status)) {
      // Taken: the address leaves the relay.
      await storage.put({ state: "accepted", job: stripped(job) });
      return null;
    }
    const refused = status.status === "cancelled" || status.status === "failed" || (status.status === "draft" && status.issues.includes("fulfilment_issue"));
    if (refused) {
      return await refuse(env, deps, storage, job, { ...facts, prodigiStatus: status.status, issues: status.issues.join(", ") },
        `${provider.name} turned the order down after it was placed (${status.status}).`);
    }
    if (status.status === "on_hold") {
      await alert(env, deps, storage, "on-hold", "an order is on hold", { ...facts, issues: status.issues.join(", ") },
        `${provider.name} holds the order (${status.issues.join(", ") || "no reason given"}): payment_required means it couldn't bill your account. Fix it in its dashboard and the order goes on; the painter has paid.`);
      return HOUR;
    }
    return retry(storage, job, null);
  }
  return null;
}

/** The job without the painter's name and address, which leave the relay once it is settled. */
function stripped(job) {
  return { key: job.key, reference: job.reference, provider: job.provider, since: job.since };
}

/** The order refused for good: the payment given back, and Paul told. */
async function refuse(env, deps, storage, job, facts, what) {
  const refunded = await refund(env, deps, facts.charge, facts.key);
  await storage.put({ state: "refused", refunded: Boolean(facts.charge) && refunded, job: stripped(job) });
  await alert(env, deps, storage, "refused", refunded || !facts.charge ? "an order was refused" : "a refund failed", { ...facts, refunded: facts.charge ? String(refunded) : "nothing was charged" },
    `${what} ${facts.charge ? (refunded ? "The payment was refunded." : "Refunding the payment FAILED: refund it by hand in Stripe.") : ""}`);
  return null;
}

/** The next try after a step that didn't settle: a minute, doubling to an hour. */
async function retry(storage, job, what, error) {
  if (what) log(what, error);
  const tries = (job.tries ?? 0) + 1;
  await storage.put({ job: { ...job, tries } });
  return Math.min(60_000 * 2 ** Math.min(tries - 1, 6), HOUR);
}

/**
 * Files an issue in the feedback repository (FEEDBACK_REPO, with FEEDBACK_GITHUB_TOKEN) for money
 * or an order that needs Paul: once per order and kind. The painter's name and address stay out.
 */
async function alert(env, deps, storage, kind, title, facts, what) {
  if (storage && (await storage.get(`alerted-${kind}`))) return;
  const sent = await fileIssue(env, deps, title, facts, what);
  if (sent && storage) await storage.put({ [`alerted-${kind}`]: true });
}

export async function fileIssue(env, deps, title, facts, what) {
  log(`One Big Sheet: ${title} (${facts.reference ?? facts.key ?? ""})`);
  if (!env.FEEDBACK_REPO || !env.FEEDBACK_GITHUB_TOKEN) return false;
  const test = /^(sk|rk)_test_/.test(env.STRIPE_SECRET_KEY ?? "") ? "test/" : "";
  const lines = Object.entries(facts).filter(([, v]) => v !== undefined && v !== null && v !== "").map(([k, v]) => `- ${k}: \`${String(v)}\``);
  if (facts.charge) lines.push(`- Stripe: https://dashboard.stripe.com/${test}payments/${facts.charge}`);
  try {
    const response = await (deps.fetch ?? fetch)(`https://api.github.com/repos/${env.FEEDBACK_REPO}/issues`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.FEEDBACK_GITHUB_TOKEN}`,
        accept: "application/vnd.github+json",
        "x-github-api-version": "2022-11-28",
        "user-agent": "moonlight-feedback-relay",
        "content-type": "application/json",
      },
      body: JSON.stringify({ title: `One Big Sheet: ${title}`, body: `${what}\n\n${lines.join("\n")}\n` }),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return true;
  } catch (error) {
    log("Filing the issue failed", error);
    return false;
  }
}

/**
 * Once a day (worker.js's `scheduled`): every payment for a sheet in the last three days, taken
 * and not refunded, should belong to an order the print service accepted. One that doesn't, an
 * hour on, is an issue for Paul, unless its order is refunded, already alerted (stuck,
 * refused), or still being worked on and young enough that its alarm will alert should it stop.
 */
export async function reconcilePrints(env, deps = {}) {
  if (!env.STRIPE_SECRET_KEY || !env.PRINT_SHEETS) return 0;
  const now = (deps.now ?? Date.now)();
  const since = Math.floor((now - 3 * 24 * HOUR) / 1000);
  const intents = [];
  try {
    let after = "";
    for (let page = 0; page < 10; page++) {
      const listed = await stripeGet(env, deps, `/payment_intents?limit=100&created[gte]=${since}${after}`);
      const data = listed?.data ?? [];
      intents.push(...data);
      if (!listed?.has_more || data.length === 0) break;
      after = `&starting_after=${encodeURIComponent(data[data.length - 1].id)}`;
    }
  } catch (error) {
    log("Reconciling: listing payments failed", error);
    if (intents.length === 0) return 0;
  }
  let flagged = 0;
  for (const intent of intents) {
    const key = intent?.metadata?.sheet;
    if (typeof key !== "string" || !HEX.test(key) || intent.status !== "succeeded") continue;
    if (now / 1000 - intent.created < 3600) continue;
    let standing = null;
    try {
      const answer = await sheetStub(env, key).fetch("https://sheet/status");
      standing = answer.ok ? await answer.json() : null;
    } catch {}
    if (standing?.state === "accepted" || standing?.refunded) continue;
    // Paul has the issue already.
    if ((standing?.state === "stuck" || standing?.state === "refused") && standing.alerted) continue;
    // Still in hand: its alarm alerts should it stop, within GIVE_UP_MS; past that, it has died.
    if (ACTIVE.has(standing?.state) && now / 1000 - intent.created < (GIVE_UP_MS + HOUR) / 1000) continue;
    // Refunded already (the restricted key reads refunds, not charges).
    try {
      const refunds = await stripeGet(env, deps, `/refunds?payment_intent=${encodeURIComponent(intent.id)}&limit=1`);
      if ((refunds?.data ?? []).some((r) => r.status === "succeeded" || r.status === "pending")) continue;
    } catch {}
    flagged++;
    await fileIssue(env, deps, "a payment with no print", { key, reference: referenceOf(key), charge: intent.id, state: standing?.state ?? "no record", order: standing?.order },
      "The daily check found a payment for a sheet whose order the print service hasn't accepted. Look the order up in Prodigi's dashboard; place it or refund the payment.");
  }
  return flagged;
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
async function chargeApplePay(env, deps, payment, priced, key, recipient) {
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
    // Stripe's default methods, without any that would send the painter to a page: Apple Pay's
    // sheet is the whole checkout.
    "automatic_payment_methods[enabled]": "true",
    "automatic_payment_methods[allow_redirects]": "never",
    "payment_method_data[type]": "card",
    "payment_method_data[card][token]": token.id,
    description: "One Big Sheet",
    "metadata[sheet]": key,
    receipt_email: recipient.email,
    "shipping[name]": recipient.name,
    "shipping[address][line1]": recipient.line1,
    ...(recipient.line2 ? { "shipping[address][line2]": recipient.line2 } : {}),
    "shipping[address][city]": recipient.city,
    ...(recipient.state ? { "shipping[address][state]": recipient.state } : {}),
    "shipping[address][postal_code]": recipient.zip,
    "shipping[address][country]": recipient.country,
  });
  if (typeof intent?.id !== "string") throw Object.assign(new Error("Stripe's answer had no payment"), { uncertain: true });
  if (intent.status !== "succeeded") {
    // requires_action and the like: nothing was taken, and Apple Pay's sheet is gone.
    throw Object.assign(new Error(`Stripe's payment is ${intent.status}`), { declined: true });
  }
  return intent.id;
}

/** Gives a payment back (an order the print service refused); says whether it did. */
async function refund(env, deps, charge, key) {
  if (!charge) return false;
  try {
    await stripe(env, deps, "/refunds", `${key}-refund`, { payment_intent: charge });
    return true;
  } catch (error) {
    log(`Refunding ${charge} failed`, error);
    return false;
  }
}

/** The payment Stripe holds for an order, by its metadata (`chargeApplePay`), or null. */
async function paymentOf(env, deps, key) {
  const query = encodeURIComponent(`metadata['sheet']:'${key}'`);
  const found = await stripeGet(env, deps, `/payment_intents/search?query=${query}`);
  const intents = found?.data ?? [];
  return intents.find((intent) => intent.status === "succeeded") ?? intents[0] ?? null;
}

/** A read of Stripe's API; any failure throws (the caller tries again later). */
async function stripeGet(env, deps, path) {
  const response = await (deps.fetch ?? fetch)(`${STRIPE}${path}`, {
    method: "GET",
    headers: { authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
  });
  if (!response.ok) throw new Error(`Stripe GET ${path.split("?")[0]}: HTTP ${response.status}`);
  return await response.json();
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

// MARK: The check

const CHECK_API = "https://api.anthropic.com/v1/messages";
const CHECK_MODEL = "claude-opus-5-5";
/** Checks a day, at most, unless CHECK_DAILY_LIMIT says otherwise: one costs a few cents. */
const CHECK_DAILY_LIMIT = 40;
const CHECK_TRIES = 3;
/** How long an order waits for a check still under way before it is charged all the same. */
const VERDICT_WAIT_MS = 10_000;
/** The PrintSheet that counts the day's checks (never a key: those are hex). */
const CHECK_BUDGET = "check-budget";

const CHECK_PROMPT = `You check sheets before a small print shop prints them. A customer of a paint-by-numbers app \
ordered this sheet: a line drawing with numbered areas, traced on their phone from a picture they \
chose. You see only the sheet. The shop is liable for what it prints, so it won't print a sheet \
that blatantly copies someone else's protected work or is unlawful. Almost every sheet is fine: \
people print their own photos (family, pets, places, food, flowers) and old artworks in the public \
domain (anything painted before about 1930), and those must pass.

Answer "refuse" only when it is blatant:
- a recognizable copyrighted character or franchise (cartoon, comic, film, game or anime \
characters), or a brand's logo or trademark as the subject;
- a recognizable artwork, illustration or photograph by someone else that is still in copyright \
(a famous modern painting, poster, album or book cover);
- sexual content, anything sexual involving a minor, or content that is clearly illegal or hateful \
(extremist symbols used approvingly).
Answer "hold" when it could be one of those but you can't be sure; a person will look.
Answer "pass" for everything else. Don't try to identify who a person in the picture is: a \
portrait is a pass unless it is plainly one of the cases above. Ordinary nudity in fine art is a \
pass. Text or a small logo incidental to a photo (a shirt, a street sign) is a pass.

Give the reason in one short sentence for the shop's owner.`;

const VERDICT_SCHEMA = {
  type: "object",
  properties: {
    verdict: { type: "string", enum: ["pass", "hold", "refuse"] },
    reason: { type: "string" },
  },
  required: ["verdict", "reason"],
  additionalProperties: false,
};

/**
 * Claude's look at a kept sheet, by its URL (Anthropic fetches it, as Prodigi does): {verdict:
 * "pass" | "hold" | "refuse", reason}, with `again` when no answer came and a later try may get
 * one. A day over CHECK_DAILY_LIMIT, a refusal to answer, or an answer that isn't one holds it.
 */
export async function checkSheet(env, deps, sheetUrl) {
  if (!(await spendCheck(env))) return { verdict: "hold", reason: "Over today's limit of checks: not checked." };
  let response, text;
  try {
    response = await (deps.fetch ?? fetch)(CHECK_API, {
      method: "POST",
      headers: { "x-api-key": env.ANTHROPIC_API_KEY, "anthropic-version": "2026-10-21", "content-type": "application/json" },
      body: JSON.stringify({
        model: env.CHECK_MODEL || CHECK_MODEL,
        max_tokens: 4096,
        system: CHECK_PROMPT,
        output_config: { effort: "low", format: { type: "json_schema", schema: VERDICT_SCHEMA } },
        messages: [{
          role: "user",
          content: [
            { type: "document", source: { type: "url", url: sheetUrl } },
            { type: "text", text: "The sheet to print. Your verdict?" },
          ],
        }],
      }),
    });
    text = await response.text();
  } catch (error) {
    log("The check got no answer", error);
    return { verdict: "hold", reason: "The check got no answer.", again: true };
  }
  if (!response.ok) {
    // Its error type alone, never the body's echo of the request.
    let type = "";
    try {
      type = String(JSON.parse(text)?.error?.type ?? "").slice(0, 60);
    } catch {}
    log(`The check failed: HTTP ${response.status} ${type}`);
    const again = response.status === 429 || response.status >= 500;
    return { verdict: "hold", reason: `The check failed (HTTP ${response.status} ${type}).`, again };
  }
  try {
    const message = JSON.parse(text);
    if (message.stop_reason === "refusal") return { verdict: "hold", reason: "The checker declined to look at this sheet." };
    if (message.stop_reason === "max_tokens") return { verdict: "hold", reason: "The check ran out of room to answer.", again: true };
    const answer = JSON.parse(message.content.find((block) => block.type === "text").text);
    if (!["pass", "hold", "refuse"].includes(answer.verdict) || typeof answer.reason !== "string") throw new Error("no verdict");
    // The reason goes into an issue: no Markdown, mentions or links of the model's own.
    return { verdict: answer.verdict, reason: answer.reason.replace(/[`@<>\[\]()*_#|\\]/g, " ").slice(0, 300) };
  } catch (error) {
    log("The check's answer wasn't one", error);
    return { verdict: "hold", reason: "The check's answer wasn't readable." };
  }
}

/** Counts one check against today's limit; says whether it is within it. */
async function spendCheck(env) {
  const limit = Number(env.CHECK_DAILY_LIMIT) > 0 ? Number(env.CHECK_DAILY_LIMIT) : CHECK_DAILY_LIMIT;
  try {
    const answer = await sheetStub(env, CHECK_BUDGET).fetch("https://sheet/spend", { method: "POST", headers: { "x-limit": String(limit) } });
    if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
    const counted = await answer.json();
    if (!counted.ok) log(`Over today's ${limit} checks: the sheet is held`);
    return counted.ok === true;
  } catch (error) {
    log("Counting the check failed", error);
    return false;
  }
}

/** The check's verdict once it is in, asked every second for VERDICT_WAIT_MS; undefined if not. */
async function awaitVerdict(stub, deps) {
  const now = deps.now ?? Date.now;
  const sleep = deps.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  const until = now() + VERDICT_WAIT_MS;
  for (;;) {
    try {
      const answer = await stub.fetch("https://sheet/status");
      if (answer.ok) {
        const status = await answer.json();
        if (!status.checking) return status.verdict;
      }
    } catch (error) {
      log("Reading the check's verdict failed", error);
      return undefined;
    }
    if (now() >= until) return undefined;
    await sleep(1000);
  }
}

/** The review page of a held order (GET) and Paul's decision on it (POST, a form). */
async function review(request, env, rest) {
  const match = /^([0-9a-f]{32})\/([0-9a-f]{32})$/.exec(rest);
  if (!match || !env.PRINT_SHEETS) return bare(404);
  const [, key, token] = match;
  const stub = sheetStub(env, key);
  if (request.method === "POST") {
    let decision = null;
    try {
      decision = (await request.formData()).get("decision");
    } catch {}
    const answer = await stub.fetch("https://sheet/review", { method: "POST", headers: { "x-review": token, "x-decision": String(decision) } });
    if (answer.status === 404) return bare(404);
    const done = answer.ok ? (decision === "release" ? "It goes to the printer now." : "It is refunded now.")
      : answer.status === 400 ? "Choose Print it or Refund it." : "It was decided already.";
    return page(`<p>${done}</p>`);
  }
  if (request.method !== "GET") return bare(405, { allow: "GET, POST" });
  const answer = await stub.fetch("https://sheet/held", { headers: { "x-review": token } });
  if (!answer.ok) return bare(404);
  const held = await answer.json();
  const sheetUrl = `${SHEETS}${key}/${held.token}.pdf`;
  const decided = held.state !== "held" || held.review;
  return page(`<h1>Order ${escapeHTML(held.reference ?? "")}</h1>
<p>The check held this sheet: ${escapeHTML(held.reason ?? "no reason given")}</p>
<p><a href="${sheetUrl}">Look at the sheet</a></p>
${decided ? `<p>Decided: ${escapeHTML(held.review ?? held.state)}.</p>` : `<form method="post"><button name="decision" value="release">Print it</button> <button name="decision" value="refuse">Refund it</button></form>`}`);
}

function page(body) {
  return new Response(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta name="robots" content="noindex"><title>One Big Sheet</title><body style="font: 17px system-ui; margin: 2em auto; max-width: 32em; padding: 0 1em">${body}</body>`, {
    status: 200, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" },
  });
}

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

async function digestOf(bytes) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
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
 * order: the PDF in chunks (a stored value is at most 2 MB), its random token, the state, the
 * payment and order ids, the job (what to place and where; the address only until the print
 * service has accepted it), and one alarm, which works the order (`advance`) and, once it is
 * settled, deletes it all SHEET_DAYS after the sheet was kept.
 *   States: "new" (kept, not ordered), "charging", "charged" or "queued" (unpaid, the sandbox's),
 *   "placing", "placed" (the service has it, not yet seen accepted), "accepted", "refused"
 *   (refunded), "stuck" (given up on, an issue filed), "held" (the check wasn't sure: Paul's to
 *   decide on the review page, refunded after HOLD_MS). With the check, also `check` ("due",
 *   "done"), `verdict` ({verdict, reason}) and the review's token and decision.
 *   POST https://sheet/keep   the PDF as the body; x-days. Keeps it, or replaces it while the order
 *                             is "new" and no try holds it; after that the order's sheet stays.
 *   POST https://sheet/begin  {state, token, charge?, order?, claim?}, or 404 with no sheet. The
 *                             claim goes to the one try that may take the order on: the first, or
 *                             one coming after a claim left "new" for CLAIM_MS (its try gone).
 *   POST https://sheet/mark   x-claim; {state, charge?, order?, job?, alarmIn?}
 *   POST https://sheet/drop   x-claim; the order back to "new", free (it surely failed)
 *   GET  https://sheet/read   x-token; the PDF, or 404
 *   GET  https://sheet/status {state, order?, charge?, refunded, alerted, checking, verdict?}, or 404
 *   GET  https://sheet/held   x-review; what the review page shows
 *   POST https://sheet/review x-review, x-decision (release | refuse); once, while held
 *   POST https://sheet/spend  x-limit; only the object CHECK_BUDGET: counts a check, today's
 */
export class PrintSheet {
  constructor(state, env, deps = {}) {
    this.storage = state.storage;
    this.env = env ?? {};
    this.deps = deps;
  }

  now() {
    return (this.deps.now ?? Date.now)();
  }

  async fetch(request) {
    const { pathname } = new URL(request.url);
    if (pathname === "/keep" && request.method === "POST") {
      const days = Number(request.headers.get("x-days"));
      if (!(days > 0)) return bare(400);
      // The body first: storage calls hold the object's input gate, so between the look and the
      // write below no other try of the order runs; reading a request body doesn't.
      const bytes = new Uint8Array(await request.arrayBuffer());
      const kept = await this.storage.get(["token", "state", "claimedAt", "chunks"]);
      const free = kept.get("state") === "new" && this.now() - (kept.get("claimedAt") ?? 0) > CLAIM_MS;
      if (kept.get("token") && !free) return json(200, { kept: true });
      const chunks = Math.ceil(bytes.byteLength / CHUNK);
      // A put takes at most 128 keys: a sheet is at most 25 chunks.
      const entries = { chunks };
      for (let i = 0; i < chunks; i++) entries[`chunk-${i}`] = bytes.slice(i * CHUNK, (i + 1) * CHUNK);
      for (let i = chunks; i < (kept.get("chunks") ?? 0); i++) await this.storage.delete?.(`chunk-${i}`);
      await this.storage.put(entries);
      // The token last: a sheet with a token is whole.
      const expires = this.now() + days * 24 * HOUR;
      await this.storage.put({ token: kept.get("token") ?? randomHex(), state: "new", claimedAt: 0, expires });
      // A new sheet is checked at once (the alarm), unless these very bytes have their answer.
      const digest = await digestOf(bytes);
      const origin = request.headers.get("x-origin");
      const key = request.headers.get("x-key");
      if (this.env.ANTHROPIC_API_KEY && origin && key && digest !== (await this.storage.get("digest"))) {
        await this.storage.put({ check: "due", checkTries: 0, digest, origin, key, sheetVersion: ((await this.storage.get("sheetVersion")) ?? 0) + 1 });
        await this.storage.delete?.("verdict");
        await this.storage.setAlarm(this.now());
      } else {
        // The same bytes: their answer stands, or their check, still due, goes on.
        await this.storage.setAlarm((await this.storage.get("check")) === "due" ? this.now() : expires);
      }
      return json(201, { kept: true });
    }
    if (pathname === "/begin" && request.method === "POST") {
      const kept = await this.storage.get(["token", "state", "charge", "order", "claimedAt", "refunded", "check", "verdict"]);
      if (!kept.get("token")) return bare(404);
      const answer = { token: kept.get("token"), state: kept.get("state"), charge: kept.get("charge"), order: kept.get("order"), refunded: kept.get("refunded") === true,
        checking: kept.get("check") === "due", verdict: kept.get("verdict")?.verdict };
      if (kept.get("state") === "new" && this.now() - (kept.get("claimedAt") ?? 0) > CLAIM_MS) {
        answer.claim = randomHex();
        await this.storage.put({ claim: answer.claim, claimedAt: this.now() });
      }
      return json(200, answer);
    }
    if (pathname === "/mark" && request.method === "POST") {
      let next;
      try {
        next = JSON.parse(await request.text());
      } catch {
        return bare(400);
      }
      if (!(await this.storage.get("token")) || typeof next?.state !== "string") return bare(404);
      if ((await this.storage.get("claim")) !== request.headers.get("x-claim")) return bare(409);
      const entries = { state: next.state };
      if (typeof next.charge === "string") entries.charge = next.charge;
      if (typeof next.order === "string") entries.order = next.order;
      if (next.job && typeof next.job === "object") entries.job = next.job;
      await this.storage.put(entries);
      if (typeof next.alarmIn === "number") await this.storage.setAlarm(this.now() + Math.max(0, next.alarmIn));
      return json(200, { ok: true });
    }
    if (pathname === "/drop" && request.method === "POST") {
      if ((await this.storage.get("claim")) !== request.headers.get("x-claim")) return bare(409);
      await this.storage.put({ state: "new", claimedAt: 0 });
      await this.storage.delete?.("job");
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
    if (pathname === "/status" && request.method === "GET") {
      const kept = await this.storage.get(["state", "order", "charge", "refunded", "alerted-stuck", "alerted-refused", "alerted-unsure"]);
      if (!kept.get("state")) return bare(404);
      const alerted = ["stuck", "refused", "unsure"].some((kind) => kept.get(`alerted-${kind}`) === true);
      const check = await this.storage.get(["check", "verdict"]);
      return json(200, { state: kept.get("state"), order: kept.get("order"), charge: kept.get("charge"), refunded: kept.get("refunded") === true, alerted,
        checking: check.get("check") === "due", verdict: check.get("verdict")?.verdict });
    }
    if (pathname === "/held" && request.method === "GET") {
      const kept = await this.storage.get(["reviewToken", "state", "job", "verdict", "token", "review"]);
      if (!kept.get("reviewToken") || kept.get("reviewToken") !== request.headers.get("x-review")) return bare(404);
      return json(200, { state: kept.get("state"), reference: kept.get("job")?.reference, reason: kept.get("verdict")?.reason, token: kept.get("token"), review: kept.get("review") });
    }
    if (pathname === "/review" && request.method === "POST") {
      const decision = request.headers.get("x-decision");
      const kept = await this.storage.get(["reviewToken", "state"]);
      if (!kept.get("reviewToken") || kept.get("reviewToken") !== request.headers.get("x-review")) return bare(404);
      if (decision !== "release" && decision !== "refuse") return bare(400);
      if (kept.get("state") !== "held" || (await this.storage.get("review"))) return bare(409);
      await this.storage.put({ review: decision });
      await this.storage.setAlarm(this.now());
      return json(200, { ok: true });
    }
    if (pathname === "/spend" && request.method === "POST") {
      // Only the object named CHECK_BUDGET: today's checks, counted against the day's limit.
      const limit = Number(request.headers.get("x-limit"));
      const day = new Date(this.now()).toISOString().slice(0, 10);
      const spent = (await this.storage.get(`spent-${day}`)) ?? 0;
      if (!(spent < limit)) return json(200, { ok: false, spent });
      const last = await this.storage.get("lastDay");
      if (last && last !== day) await this.storage.delete?.(`spent-${last}`);
      await this.storage.put({ [`spent-${day}`]: spent + 1, lastDay: day });
      return json(200, { ok: true, spent: spent + 1 });
    }
    return bare(404);
  }

  /**
   * The check of the kept sheet (`checkSheet`); its answer stored unless the sheet was replaced
   * meanwhile. Answers how long until it is tried again (no answer, three times), or null.
   */
  async runCheck() {
    const kept = await this.storage.get(["token", "origin", "key", "sheetVersion", "checkTries"]);
    const version = kept.get("sheetVersion");
    const result = await checkSheet(this.env, this.deps, `${kept.get("origin")}${SHEETS}${kept.get("key")}/${kept.get("token")}.pdf`);
    // A sheet sent again while this one was looked at is checked anew, at once.
    if ((await this.storage.get("sheetVersion")) !== version) return 0;
    const tries = (kept.get("checkTries") ?? 0) + 1;
    if (result.again && tries < CHECK_TRIES) {
      await this.storage.put({ checkTries: tries });
      return 30_000;
    }
    await this.storage.put({ check: "done", verdict: { verdict: result.verdict, reason: result.reason } });
    return null;
  }

  /** Works the order a step on while one is under way; otherwise deletes it all once it is due. */
  async alarm() {
    if ((await this.storage.get("check")) === "due") {
      const wait = await this.runCheck();
      if (wait !== null) {
        await this.storage.setAlarm(this.now() + wait);
        return;
      }
    }
    const names = ["state", "job", "charge", "order", "token", "expires", "check", "verdict", "review", "reviewToken", "heldAt", "released"];
    const kept = await this.storage.get(names);
    const standing = Object.fromEntries(names.map((name) => [name, kept.get(name)]));
    if (standing.job && ACTIVE.has(standing.state)) {
      standing.key = standing.job.key;
      let next;
      try {
        next = await advance(this.env, this.deps, this.storage, standing);
      } catch (error) {
        log(`Working order ${standing.job.reference} failed`, error);
        next = await retry(this.storage, standing.job, null);
      }
      if (next !== null) {
        await this.storage.setAlarm(this.now() + next);
        return;
      }
    }
    const expires = (await this.storage.get("expires")) ?? 0;
    // A check still due keeps the alarm near, whatever else ran.
    if ((await this.storage.get("check")) === "due") {
      await this.storage.setAlarm(this.now() + 30_000);
      return;
    }
    if (this.now() >= expires) {
      await this.storage.deleteAll();
      return;
    }
    await this.storage.setAlarm(expires);
  }
}

// MARK: Prodigi's API

/** One call of Prodigi's API; no answer, or a 5xx, is `uncertain` (it may have acted). */
async function prodigiCall(env, deps, method, path, body, headers = {}) {
  const fetcher = deps.fetch ?? fetch;
  let response, text;
  try {
    response = await fetcher(`${env.PRODIGI_API}${path}`, {
      method,
      headers: { "x-api-key": prodigiKey(env), ...(body === undefined ? {} : { "content-type": "application/json" }), ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    text = await response.text();
  } catch (error) {
    throw Object.assign(new Error(`Prodigi ${method} ${path}: ${error?.message ?? error}`), { uncertain: true });
  }
  if (!response.ok) {
    // Its error type alone: the body may echo the address, which is kept nowhere here.
    let outcome = "";
    try {
      outcome = String(JSON.parse(text)?.type ?? "").slice(0, 60);
    } catch {}
    const error = new Error(`Prodigi ${method} ${path}: HTTP ${response.status} ${outcome}`);
    // Busy, a conflict, a timeout or our own key refused: tried again, never taken as a refusal.
    const uncertain = response.status >= 500 || [401, 403, 408, 409, 429].includes(response.status);
    throw Object.assign(error, { uncertain, status: response.status });
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Prodigi ${method} ${path}: not JSON`);
  }
}

/**
 * The key as Prodigi's v5 sandbox takes it: the sandbox dashboard's key, `sandbox_` before it (the
 * secret may hold it with or without). Null for a live key, which this relay never sends.
 */
function prodigiKey(env) {
  const key = String(env.PRODIGI_API_KEY ?? "").trim();
  if (!key || key.startsWith("live_")) return null;
  return key.startsWith("sandbox_") ? key : `sandbox_${key}`;
}

/** A postcode of each country the app sends to, for a quote's stand-in address. */
const POSTCODES = {
  US: "10001", CA: "M5V 2T6", GB: "SW1A 1AA", IE: "D02 X285", AU: "2000", NZ: "6011", DE: "10115", FR: "75001",
  ES: "28001", IT: "00118", NL: "1012 JS", BE: "1000", AT: "1010", CH: "8001", SE: "111 52", NO: "0150", DK: "1050",
  FI: "00100", PT: "1100-148", JP: "100-0001",
};

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

async function readBytesCapped(request, limit) {
  if (!request.body) return new Uint8Array(0);
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
  return new Uint8Array(await new Blob(chunks).arrayBuffer());
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
