#!/usr/bin/env python3
"""A copy of the Xcode project that signs the app for Paint Together on real devices
(tools/together-e2e/run.sh; painting-company row 350).

    prepare.py <project.pbxproj> [--mac]

Edits the given project file in place (run it on a scratch worktree's copy, never the repository's):
the app target's Debug build signs with `Config/AppStore.entitlements` (the app group and SharePlay's
group-session, which Debug's `Outside.entitlements` lacks), and with --mac it also runs on a Mac with
Apple silicon as "Designed for iPad" (`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, which xcodebuild won't
take from its command line before it has matched the destination). The extensions and test bundles
are left alone: an entitlements override on xcodebuild's command line reaches every target, and they
have no SharePlay. Fails if the project no longer looks as expected.
"""
import re, sys

path = sys.argv[1]
mac = "--mac" in sys.argv[2:]
text = open(path).read()
APP = "PRODUCT_BUNDLE_IDENTIFIER = com.pbordjadze.paintbynumber;"
blocks = list(re.finditer(r"\t\t[0-9A-F]{24} /\* (\w+) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;.*?\n\t\t\};\n", text, re.S))
app = [b for b in blocks if APP in b.group(0)]
if len(app) != 3:
    sys.exit(f"expected the app target's 3 configurations, found {len(app)}")
out, last, changed = [], 0, 0
for b in app:
    body = b.group(0)
    if b.group(1) == "Debug":
        new = body.replace("CODE_SIGN_ENTITLEMENTS = Config/Outside.entitlements;", "CODE_SIGN_ENTITLEMENTS = Config/AppStore.entitlements;")
        if new == body:
            sys.exit("the app's Debug configuration doesn't sign with Config/Outside.entitlements any more")
        if mac:
            new2 = new.replace("SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES;")
            if new2 == new:
                sys.exit("the app's Debug configuration has no SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO")
            new = new2
        out.append(text[last:b.start()]); out.append(new); last = b.end(); changed += 1
out.append(text[last:])
if changed != 1:
    sys.exit("no Debug configuration for the app")
open(path, "w").write("".join(out))
print(f"prepared {path}" + (" (Mac too)" if mac else ""))
