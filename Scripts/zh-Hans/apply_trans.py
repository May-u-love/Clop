"""Apply translations to Clop sources at exact call-site offsets (right-to-left per file)."""
import sys, json, glob, os
sys.path.insert(0, "/tmp")
from trans_part1 import T1
from trans_part2 import T2
from trans_part3 import T3
from trans_patch import T4
from trans_patch import T4

T = {**T1, **T2, **T3, **T4}

APIS = ["Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField",
        "Section", "Menu", "Stepper", "LabeledContent", "ShareLink"]
MODS = [".help", ".navigationTitle", ".alert", ".confirmationDialog", ".subtitle"]
PARAMS = ["title:", "help:", "details:", "subtitle:"]

def extract_literal(src, i):
    j = i + 1; depth = 0
    while j < len(src):
        c = src[j]
        if c == "\\":
            if j + 1 < len(src) and src[j+1] == "(":
                depth += 1; j += 2; continue
            j += 2; continue
        if depth > 0:
            if c == "(": depth += 1
            elif c == ")": depth -= 1
            j += 1; continue
        if c == '"':
            return src[i:j+1], j + 1
        j += 1
    return None, j

sites = {}  # file -> list[(offset, literal)]
def record(fp, off, lit):
    sites.setdefault(fp, []).append((off, lit))

files = [f for f in glob.glob("/tmp/clop-src/**/*.swift", recursive=True)
         if "/ClopCLI/" not in f and "/.build/" not in f]
for fp in files:
    src = open(fp).read()
    for tok in [f'{a}("' for a in APIS] + [f'{m}("' for m in MODS]:
        start = 0
        while True:
            k = src.find(tok, start)
            if k < 0: break
            start = k + len(tok)
            qi = k + len(tok) - 1
            if src[max(0, qi-12):qi].endswith("verbatim:"):
                continue
            lit, end = extract_literal(src, qi)
            if lit: record(fp, qi, lit)
    for tok in PARAMS:
        start = 0
        while True:
            k = src.find(tok, start)
            if k < 0: break
            start = k + len(tok)
            # skip whitespace
            j = start
            while j < len(src) and src[j] in " \t":
                j += 1
            if j < len(src) and src[j] == '"':
                lit, end = extract_literal(src, j)
                if lit: record(fp, j, lit)

total = 0; replaced = 0
unmatched = {}
for fp, ss in sites.items():
    seen = set(); uniq = []
    for off, lit in sorted(ss, key=lambda x: -x[0]):
        if off in seen:
            continue
        seen.add(off)
        uniq.append((off, lit))
    ss = uniq
    last_start = None
    for off, lit in ss:
        total += 1
        new = T.get(lit)
        if new is None or new == lit:
            unmatched[lit] = unmatched.get(lit, 0) + 1
            continue
        if last_start is not None and off + len(lit) > last_start:
            continue
        src = src[:off] + new + src[off + len(lit):]
        last_start = off
        replaced += 1
    open(fp, "w").write(src)

print(f"sites: {total}, replaced: {replaced}, left as-is: {total - replaced}")
left = sorted(unmatched.items(), key=lambda x: -x[1])
print(f"distinct untranslated literals: {len(left)}")
json.dump([l for l, _ in left], open("/tmp/clop_left.json", "w"), indent=0)
