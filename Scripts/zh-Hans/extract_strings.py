"""Extract user-visible string literals from SwiftUI call sites in Clop sources."""
import re, json, glob, os

APIS = ["Text", "Button", "Label", "Toggle", "Picker", "TextField", "SecureField",
        "Section", "Menu", "Stepper", "LabeledContent", "ShareLink"]
MODIFIERS = [".help", ".navigationTitle", ".alert", ".confirmationDialog", ".subtitle"]

def extract_literal(src, i):
    """src[i] points at opening quote. Return (literal, end_index_after_quote) handling \\(...) interpolation."""
    assert src[i] == '"'
    j = i + 1
    depth = 0
    while j < len(src):
        c = src[j]
        if c == "\\":
            if j + 1 < len(src) and src[j+1] == "(":
                depth += 1
                j += 2
                continue
            j += 2
            continue
        if depth > 0:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            j += 1
            continue
        if c == '"':
            return src[i:j+1], j + 1
        j += 1
    return None, j

def is_verbatim(src, i):
    """Check if the token before the string is 'verbatim:'."""
    before = src[max(0, i-12):i]
    return before.endswith("verbatim:")

out = {}
files = [f for f in glob.glob("/tmp/clop-src/**/*.swift", recursive=True)
         if "/ClopCLI/" not in f and "/.build/" not in f]
tokens = [f'{a}("' for a in APIS] + [f'{m}("' for m in MODIFIERS]
for fp in files:
    src = open(fp).read()
    lines = src.split("\n")
    for tok in tokens:
        start = 0
        while True:
            k = src.find(tok, start)
            if k < 0:
                break
            start = k + len(tok)
            qi = k + len(tok) - 1
            lit, end = extract_literal(src, qi)
            if lit is None:
                continue
            if is_verbatim(src, qi):
                continue
            line = src[:k].count("\n") + 1
            key = f"{tok[:-1]}|{lit}"
            out.setdefault(key, []).append(f"{os.path.relpath(fp, '/tmp/clop-src')}:{line}")

json.dump(out, open("/tmp/clop_strings.json", "w"), indent=1)
uniq = {}
for key, locs in out.items():
    api, lit = key.split("|", 1)
    uniq[lit] = uniq.get(lit, 0) + len(locs)
print(f"call sites: {sum(len(v) for v in out.values())}, unique literals: {len(uniq)}")
# save unique list for translation
json.dump(sorted(uniq.keys()), open("/tmp/clop_unique.json", "w"), indent=0)
