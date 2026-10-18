#!/usr/bin/env python3
"""Summarize Paul's Claude Code sessions for the front desk.

    sessions.py <list_sessions output> [--since <ISO time>] [--previous <snapshot.json>]
                [--save <snapshot.json>] [--json] [--dashboard <dir> --backlog docs/backlog.md]

<list_sessions output> is the text `list_sessions` (claude-code-remote, `mine: true`) returned,
or the file the harness saved it to when it was too long. Prints one row per session touched
since --since (default: the last 24 hours): status, what it needs from Paul, branch, model and
effort, context used, cost so far, and with --previous the cost since that snapshot. Ends with
the account's rate-limit state and the totals. --save writes this run's snapshot ({session id: cost})
for the next --previous; --previous also takes the status page's stored `{"costs": {...}}`.
--dashboard writes the status page's three data files there: sessions.json, inbox.json (the
table of --backlog) and account.json. Nothing here talks to the network.
"""

import argparse
import datetime as dt
import json
import sys


def load_sessions(path):
    text = open(path, encoding="utf-8").read()
    start, end = text.index('{"ccr"'), text.rindex("}") + 1
    return json.loads(text[start:end])["ccr"]["data"]


def row(session):
    meta = session.get("external_metadata") or {}
    context = session.get("session_context") or {}
    usage = meta.get("usage") or {}
    summary = meta.get("post_turn_summary") or session.get("post_turn_summary") or {}
    branches = [b for b in (meta.get("current_branches") or {}).values() if b]
    return {
        "id": session["id"],
        "title": session.get("title", ""),
        "updated": session.get("updated_at", ""),
        "status": session.get("status_bucket", session.get("session_status", "")).rsplit("_", 1)[-1].lower(),
        "needs": summary.get("needs_action", ""),
        "doing": summary.get("status_detail", ""),
        "branch": branches[0] if branches else "",
        "model": meta.get("last_served_model") or context.get("model", ""),
        "effort": meta.get("effort_level") or context.get("effort_level") or "",
        "context": (meta.get("context_usage") or {}).get("used_tokens") or 0,
        "cost": usage.get("cost_usd") or 0.0,
        "rate": meta.get("rate_limit_info") or {},
    }


def load_previous(path):
    if not path:
        return {}
    data = json.load(open(path))
    data = data.get("data", data)
    return data.get("costs", data)


def backlog_rows(path):
    """The rows of the backlog's table (the one headed `#`, not the CI queue above it), keyed by
    its header (`#` becomes `n`)."""
    rows, header = [], None
    for line in open(path, encoding="utf-8"):
        if not line.startswith("|"):
            header = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if header is None:
            header = ["n" if c == "#" else c.lower().replace("'", "").replace(" ", "_") for c in cells]
        elif header[0] == "n" and not set("".join(cells)) <= set("-: "):
            rows.append(dict(zip(header, cells)))
    return rows


def write_dashboard(directory, recent, rate, spent, previous, backlog):
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    keys = ("id", "title", "status", "needs", "doing", "branch", "model", "effort", "cost", "spent", "updated")
    sessions = [dict({k: r[k] for k in keys}, context_k=r["context"] // 1000,
                     latest=f"Needs you: {r['needs']}" if r["needs"] else r["doing"]) for r in recent]
    account = [{
        "checked": now,
        "rate_status": rate.get("status", "unknown"),
        "rate_window": rate.get("rateLimitType", ""),
        "resets": dt.datetime.fromtimestamp(rate["resetsAt"], dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if rate.get("resetsAt") else "",
        "overage": bool(rate.get("isUsingOverage")),
        "spent": round(spent, 2),
        "spent_since": "today" if previous else "lifetime of these sessions",
    }]
    for name, rows in (("sessions", sessions), ("account", account), ("inbox", backlog_rows(backlog) if backlog else [])):
        json.dump(rows, open(f"{directory}/{name}.json", "w"), indent=1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("listing")
    parser.add_argument("--since")
    parser.add_argument("--previous")
    parser.add_argument("--save")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--dashboard")
    parser.add_argument("--backlog")
    args = parser.parse_args()

    since = args.since or (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)).isoformat()
    rows = [row(s) for s in load_sessions(args.listing)]
    previous = load_previous(args.previous)
    recent = [r for r in rows if r["updated"] >= since[:19]]
    for r in recent:
        r["spent"] = r["cost"] - previous.get(r["id"], 0.0)

    rate = next((r["rate"] for r in sorted(rows, key=lambda r: r["updated"], reverse=True) if r["rate"]), {})
    total = sum(r["spent"] for r in recent)
    if args.save:
        json.dump({r["id"]: r["cost"] for r in rows}, open(args.save, "w"))
    if args.dashboard:
        write_dashboard(args.dashboard, recent, rate, total, previous, args.backlog)
    if args.json:
        json.dump(recent, sys.stdout, indent=1)
        return

    for r in sorted(recent, key=lambda r: r["updated"], reverse=True):
        spent = f"  +${r['spent']:.2f}" if previous else ""
        print(f"{r['title'][:38]:38} {r['status']:9} ${r['cost']:7.2f}{spent}  "
              f"{r['model'].replace('claude-', '')} {r['effort']}  ctx {r['context'] // 1000}k  {r['branch']}")
        if r["needs"]:
            print(f"    needs Paul: {r['needs']}")
        elif r["doing"]:
            print(f"    {r['doing'][:100]}")
    resets = dt.datetime.fromtimestamp(rate["resetsAt"], dt.timezone.utc).strftime("%H:%M UTC") if rate.get("resetsAt") else "?"
    print(f"\nrate limit ({rate.get('rateLimitType', '?')}): {rate.get('status', '?')}, resets {resets}"
          f"{', USING OVERAGE' if rate.get('isUsingOverage') else ''}")
    print(f"{'spent since last snapshot' if previous else 'lifetime cost of these sessions'}: ${total:.2f}")


if __name__ == "__main__":
    main()
