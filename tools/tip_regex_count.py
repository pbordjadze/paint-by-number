"""Counts the Regex parses TipKit makes in a running Debug build of the app, and who asked for them.

Attaches lldb to the app in a booted simulator, counts with breakpoints that never stop it for
long, and prints the counts after a while (painting-company row 263). Run it with Xcode's Python,
which has lldb's module:

    PYTHONPATH="$(xcrun lldb -P)" xcrun python3 tools/tip_regex_count.py --pid <pid> --seconds 90
    PYTHONPATH="$(xcrun lldb -P)" xcrun python3 tools/tip_regex_count.py --udid <udid> --until-exit
        # then start the app on that simulator, by hand or from a UI test

`--udid` waits for the app to start on that simulator alone (other simulators may be running
the app too) and attaches a moment after its launch;
`xcrun simctl launch --wait-for-debugger <udid> <bundle id> -demo <scenario>` prints the pid of
an app that waits at its first instruction, for `--pid`, so nothing is missed; `--until-file
<data container>/tmp/demo-ready --settle 10` counts until the scenario is on screen and 10 s
more, however long a loaded Mac takes to get there. It counts:

- `Regex.init(_regexString:version:)`, the parse, by the nearest caller it came through:
  TipKit's `View.popoverTip`, `Tips.Parameter`'s init (a lazy `@Parameter` first touched),
  the app's `GentleTipModifier`, TipKit's other frames, or anything else (`--stacks` prints one
  stack of each);
- TipKitCore's `String.init(type:)`, which made every parse in Instruments' stall traces, by the
  type it was asked about (the symbol of its metadata argument);
- TipKit's `View.popoverTip`, the app's `GentleTipModifier.body`, which calls it, and `TipID.tip`,
  which makes a tip value (from that body, and from anywhere).

Counts are of calls, so they don't depend on how loaded the Mac is; parses per modifier body is
the number to compare between builds. Each callback stops the app for a moment: under a UI test
pass `--fast` (lldb's own hit counts, no split by caller or type), or its queries time out.
"""

import argparse
import os
import sys
import time

import lldb

COUNTS = {}
STACKS = {}
TARGETS = [
    ("regex", r"Regex\.init\(_regexString", "libswift_StringProcessing.dylib"),
    ("stringType", r"String\.init.*\(type:", "TipKitCore"),
    ("popoverTip", r"View\.popoverTip\(", "TipKit"),
    ("gentleBody", r"^PaintByNumber\.GentleTipModifier\.body\(content:", "PaintByNumber.debug.dylib"),
    ("tipGetter", r"^PaintByNumber\.TipID\.tip\.getter", "PaintByNumber.debug.dylib"),
]


def _bump(key):
    COUNTS[key] = COUNTS.get(key, 0) + 1


def _caller_of_regex(thread):
    for i in range(1, min(thread.GetNumFrames(), 40)):
        f = thread.GetFrameAtIndex(i)
        name = f.GetFunctionName() or ""
        module = f.GetModule().GetFileSpec().GetFilename() or ""
        if "popoverTip" in name:
            return "popoverTip"
        if "Parameter" in name and module.startswith("TipKit"):
            return "parameterInit"
        if "GentleTipModifier" in name:
            return "gentleModifier"
    for i in range(1, min(thread.GetNumFrames(), 40)):
        module = thread.GetFrameAtIndex(i).GetModule().GetFileSpec().GetFilename() or ""
        if module.startswith("TipKit"):
            return "otherTipKit"
    return "elsewhere"


def regex_hit(frame, bp_loc, extra_args, internal_dict):
    thread = frame.GetThread()
    caller = _caller_of_regex(thread)
    _bump("regex")
    _bump("regex." + caller)
    if caller not in STACKS:
        STACKS[caller] = [thread.GetFrameAtIndex(i).GetFunctionName() or hex(thread.GetFrameAtIndex(i).GetPC())
                          for i in range(min(thread.GetNumFrames(), 24))]
    return False


def string_type_hit(frame, bp_loc, extra_args, internal_dict):
    _bump("stringType")
    target = frame.GetThread().GetProcess().GetTarget()
    metadata = frame.FindRegister("x0").GetValueAsUnsigned()
    symbol = target.ResolveLoadAddress(metadata).GetSymbol().GetName() or hex(metadata)
    for prefix in ("full type metadata for ", "type metadata for "):
        symbol = symbol.replace(prefix, "")
    _bump("stringType[%s]" % symbol)
    return False


def popover_hit(frame, bp_loc, extra_args, internal_dict):
    _bump("popoverTip")
    return False


def body_hit(frame, bp_loc, extra_args, internal_dict):
    _bump("gentleBody")
    return False


def tip_getter_hit(frame, bp_loc, extra_args, internal_dict):
    caller = frame.GetThread().GetFrameAtIndex(1).GetFunctionName() or ""
    _bump("tipGetter" + (".fromGentleBody" if "GentleTipModifier" in caller else ""))
    return False


CALLBACKS = {"regex": "regex_hit", "stringType": "string_type_hit", "popoverTip": "popover_hit",
             "gentleBody": "body_hit", "tipGetter": "tip_getter_hit"}


def arm(debugger, target, module_name, fast):
    """Sets the breakpoints; `fast` leaves them to count their hits themselves, with no callback
    (no split by caller or type, but quick enough for a UI test's queries to keep answering)."""
    breakpoints = {}
    for key, pattern, module in TARGETS:
        if module:
            modules = lldb.SBFileSpecList()
            modules.Append(lldb.SBFileSpec(module))
            bp = target.BreakpointCreateByRegex(pattern, modules, lldb.SBFileSpecList())
        else:
            bp = target.BreakpointCreateByRegex(pattern)
        bp.SetAutoContinue(True)
        if not fast:
            bp.SetScriptCallbackFunction("%s.%s" % (module_name, CALLBACKS[key]))
        breakpoints[key] = bp
    return breakpoints


def report(counts, stacks, show_stacks):
    lines = ["%-60s %d" % (key, counts[key]) for key in sorted(counts)]
    body = counts.get("gentleBody", 0)
    if body:
        lines.append("%-60s %.3f" % ("regex per GentleTipModifier body", counts.get("regex", 0) / body))
        lines.append("%-60s %.3f" % ("regex through popoverTip per body", counts.get("regex.popoverTip", 0) / body))
    if show_stacks:
        for caller, frames in stacks.items():
            lines.append("-- a parse through %s:" % caller)
            lines += ["   #%d %s" % (i, name) for i, name in enumerate(frames)]
    return "\n".join(lines)


def wait_for_app(udid):
    """The pid of the app once it starts on the simulator `udid` (by its executable's path), not
    counting one already running there."""
    import subprocess

    def running():
        out = subprocess.run(["ps", "-ax", "-o", "pid=,args="], capture_output=True, text=True).stdout
        for line in out.splitlines():
            pid, _, command = line.strip().partition(" ")
            if "/Devices/%s/" % udid in command and "PaintByNumber.app/PaintByNumber" in command:
                yield int(pid)

    before = set(running())
    while True:
        for pid in running():
            if pid not in before:
                return pid
        time.sleep(0.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--pid", type=int)
    parser.add_argument("--udid", help="wait for the app to start on this simulator")
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--until-exit", action="store_true", help="count until the app ends")
    parser.add_argument("--until-file", metavar="PATH",
                        help="count until this file exists (a demo's tmp/demo-ready), then --settle seconds;"
                             " --seconds stays the limit")
    parser.add_argument("--settle", type=float, default=10)
    parser.add_argument("--stacks", action="store_true")
    parser.add_argument("--fast", action="store_true", help="totals only, for a UI test")
    args = parser.parse_args()
    stopping = []
    import signal
    signal.signal(signal.SIGTERM, lambda *_: stopping.append(True))

    debugger = lldb.SBDebugger.Create()
    debugger.SetAsync(True)
    here = os.path.abspath(__file__)
    debugger.HandleCommand("command script import '%s'" % here)
    module = sys.modules[os.path.splitext(os.path.basename(here))[0]]

    target = debugger.CreateTarget("")
    listener = debugger.GetListener()
    error = lldb.SBError()
    pid = args.pid or wait_for_app(args.udid)
    process = target.AttachToProcessWithID(listener, pid, error)
    if not error.Success():
        sys.exit("attach failed: %s" % error)
    event = lldb.SBEvent()
    while process.GetState() != lldb.eStateStopped:
        listener.WaitForEvent(1, event)
    started = time.monotonic()
    breakpoints = arm(debugger, target, module.__name__, args.fast)
    print("attached to %d, armed in %.1f s" % (pid, time.monotonic() - started), file=sys.stderr, flush=True)
    process.Continue()
    deadline = None if args.until_exit else time.monotonic() + args.seconds
    ready = None
    while (deadline is None or time.monotonic() < deadline) and not stopping:
        if args.until_file and ready is None and os.path.exists(args.until_file):
            ready = time.monotonic()
            print("ready after %.1f s" % (ready - started), file=sys.stderr, flush=True)
            deadline = min(deadline or ready + args.settle, ready + args.settle)
        if listener.WaitForEvent(1, event):
            state = lldb.SBProcess.GetStateFromEvent(event)
            if state in (lldb.eStateExited, lldb.eStateDetached, lldb.eStateCrashed):
                break
    if process.GetState() not in (lldb.eStateExited, lldb.eStateDetached):
        process.Stop()
        end = time.monotonic() + 30
        while process.GetState() != lldb.eStateStopped and time.monotonic() < end:
            listener.WaitForEvent(1, event)
    counts = module.COUNTS
    if args.fast:
        counts = {key: bp.GetHitCount() for key, bp in breakpoints.items()}
    print(report(counts, module.STACKS, args.stacks), flush=True)
    if process.GetState() == lldb.eStateStopped:
        target.DeleteAllBreakpoints()
        process.Detach()


if __name__ == "__main__":
    main()
