#!/usr/bin/env bash
# forfileanchorcheck.sh — FOR-FILE-ANCHOR (issue #466, reported by @pguerrerolinares): a --for subject that IS a file resolves to
# that file (src/mention.h RawMention::whole / resolveStemFile; src/forfilepage.h) and serves its page.
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 61ab7aac; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, default regime) whose subject is a file: a bare basename with a code extension, a hyphenated or
#            snake_case file stem, a path, or a directory — nothing else but stopwords and file nouns ("file", "package", "script").
#   WHAT     <named-file p= lines= defs=> first inside the root: every def (s t= n= l= e= in= by=), and for a script its
#            top-level text (<top l= e=>CDATA</top>, <top_cut … rest=> when cut); the file's top defs rank first.
#   NOT      a name matching several files (listed in <named-files>, none picked), a file mentioned as CONTEXT in a longer
#            question (anchor lift only, no page), a word that is a symbol's name, --json, RIPWIRE_NO_FILE_PAGE=1.
#
# Arms (fixtures created at runtime in a temp dir — never under a .gitignored path):
#   A1 [P] Bash `--for=document-remind` (hyphen stem; diag-466 §repro): the page names the script, serves its top-level text
#          ("set -euo pipefail"), and the r=1/r=2 rows are the script's — not the test sibling or a decoy. The honesty arm: base
#          answered confidence="high" with a decoy head.
#   A2 [P] the same through a bare basename `document-remind.sh` and `the document-remind.sh script`
#   B1 [P] Python `--for=sync_ledger` (snake stem, no symbol of that name): not reason="no_candidates"; page present
#   B2 [P] `--for="what does sync_ledger.py do"`: page present
#   B3 [P] Ruby / Lua / JS / TS stems and basenames: page present with top-level text
#   C1 [P] ambiguous basename `util.py` (two files): <named-files n="util.py" total="2"> listing both; no <named-file> page and
#          no file-subject lift (no "file subject:" note)
#   C2 [G] a dotted Scope.name `Location.go` with NO such file keeps its dotted reading: no page, method `go` of Location in <sigs>
#   D1 [P] directory: `--for="cmd/syncledger package"` serves <named-dir p="cmd/syncledger"> holding main.go's page
#   E1 [G] context, not subject: `where STATE used in sync_ledger.py is defined` carries no page
#   E2 [G] a stem that IS a symbol's name (`run_all`, def run_all in run_all.py): no stem anchor, no page
#   F1 [P] in=0 hedge: the clause says in=0 is NOT unused; the uncalled def carries in="0"; by= names the caller's file
#   R1 [P] redaction: a secret in the top-level text is redacted (the AKIA key is absent from the answer)
#   K1 [P] the top-level cap discloses: a 120-line script shows at most 40 lines and <top_cut … rest=>
#   N1 [G] no page with RIPWIRE_NO_FILE_PAGE=1, nor under --json
#   L1 [P] the clause rides in both dialects and defines every attribute the page elements carry (whole-name search in the clause)
#   X1 [G] determinism  X2 [G] xmllint well-formed (when xmllint exists)  X3 [G] no "--" inside the legend comment
#
# Usage:  bash test/forfileanchorcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/forfileanchorcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_FILE_PAGE RIPWIRE_NO_MENTION
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forfileanchorcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

T="$( mktemp -d "${TMPDIR:-/tmp}/forfileanchor.XXXXXX" )" || exit 2
trap '[ -n "${FORFILEANCHOR_KEEP:-}" ] || rm -rf "$T"' EXIT   # FORFILEANCHOR_KEEP=1 keeps the answers for a look
H="$T/home"; mkdir -p "$H"

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
python3 - "$T" <<'PY'
import os, sys
T = sys.argv[1]
def w(rel, text):
    p = os.path.join(T, rel); os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(text)
# bash: a mostly-top-level hook script, its test sibling (names share the stem's tokens), decoys
top = ["#!/usr/bin/env bash", "# document-remind.sh: Stop hook that reminds the agent to update the journal.", "set -euo pipefail",
       'INPUT="$(cat)"', 'STATE_DIR="${HOME}/.cache/acme"', 'mkdir -p "$STATE_DIR"', 'TOKEN="AKIAABCDEFGHIJKLMNOP"']
for i in range(1, 30):
    top += ['if [ -f "$STATE_DIR/flag%d" ]; then' % i, '  echo "journal pending %d" >> "$STATE_DIR/stamp"' % i, "fi"]
top += ["emit() {", '  printf "%s\\n" "$1"', "}", 'emit "remind the document journal"']
w("bash/plugins/acme/scripts/document-remind.sh", "\n".join(top) + "\n")
w("bash/plugins/acme/scripts/test-document-remind.sh",
  "".join("test_document_remind_%d() {\n  echo document remind %d\n}\n" % (i, i) for i in range(6)))
w("bash/plugins/acme/scripts/delegar.py", "def remind(document):\n    return document\n\ndef delegate_document(d):\n    return remind(d)\n")
w("bash/src/escritor.py", "def write_document(x):\n    return x\n\ndef remind_later(x):\n    return x\n")
# python: snake stem with __main__, a test, decoys, an uncalled def and a called one
w("py/tools/sync_ledger.py", "import sys\nSTATE = {}\n\ndef emit(x):\n    print(x)\n\ndef unused_helper():\n    return 1\n\n"
  + "".join("for k%d in range(3):\n    STATE[k%d] = k%d\n" % (i, i, i) for i in range(12))
  + "if __name__ == '__main__':\n    emit(STATE)\n")
w("py/tools/test_sync_ledger.py", "from sync_ledger import emit\n\ndef test_sync_ledger_emit():\n    emit(1)\n")
w("py/src/decoy.py", "LEDGER_SYNC_TAGS = ['sync', 'ledger']\n\ndef sync_tags():\n    return LEDGER_SYNC_TAGS\n")
w("py/pkg_a/util.py", "def a_helper():\n    return 1\n")
w("py/pkg_b/util.py", "def b_helper():\n    return 2\n")
w("py/tools/run_all.py", "def run_all():\n    return 0\n\nrun_all()\n")
w("py/tools/user.py", "from sync_ledger import STATE\n\ndef reader():\n    return STATE\n")
# ruby / lua / js / ts
body = "".join("STATE[%d] = %d\n" % (i, i) for i in range(20))
w("rb/bin/sync_ledger.rb", "STATE = {}\ndef emit(x)\n  puts x\nend\n" + body.replace("STATE[", "STATE[") + "emit(STATE)\n")
w("lua/scripts/sync_ledger.lua", "local STATE = {}\nlocal function emit(x)\n  print(x)\nend\n" + body + "emit(STATE)\n")
js = "const STATE = {};\nfunction emit(x) {\n  console.log(x);\n}\n" + "".join("STATE[%d] = %d;\n" % (i, i) for i in range(20)) + "emit(STATE);\n"
w("js/scripts/sync-ledger.js", js)
w("js/scripts/sync-ledger.test.js", "function syncLedgerTest() {\n  return 'sync ledger';\n}\n")
w("ts/scripts/sync-ledger.ts", js)
# go: a directory anchor
w("go/cmd/syncledger/main.go", "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(helper())\n}\n\nfunc helper() string {\n\treturn \"x\"\n}\n")
w("go/go.mod", "module example.com/x\n\ngo 1.21\n")
# the dotted Scope.name near miss (no file Location.go anywhere)
w("ts2/src/location.ts", "export class Location {\n  go(path: string): void {\n    history.pushState(null, '', path);\n  }\n}\n")
# K1: a long script
w("long/run-deploy.sh", "#!/bin/sh\n" + "".join('echo "step %d"\n' % i for i in range(120)))
PY

run(){ local d="$1"; shift; ( cd "$T/$d" || exit 1; HOME="$H" TMPDIR="$T/" "$BIN" "$T/$d" --no-cache "$@" < /dev/null 2>/dev/null ); }
has(){ grep -qF -- "$2" "$1"; }

# ── A: the #466 Bash rows ───────────────────────────────────────────────────────────────────────────────────────────────────
run bash --for=document-remind > "$T/a1.xml"
if has "$T/a1.xml" '<named-file p="plugins/acme/scripts/document-remind.sh"' && has "$T/a1.xml" 'set -euo pipefail'; then
    ok "A1 hyphen stem: the script's page with its top-level text"
else no "A1 hyphen stem: no page for plugins/acme/scripts/document-remind.sh (or no top-level text)"; fi
head2="$( python3 - "$T/a1.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
rows = {int(r): p for p, r in re.findall(r'<(?:d|h) [^>]*?p="([^"]*)"[^>]*? r="(\d+)"', s)}
print(" ".join(rows.get(k, "-") for k in (1, 2)))
PY
)"
case "$head2" in
    *plugins/acme/scripts/document-remind.sh*) ok "A1 the ranked head (r=1/r=2) is the named script: $head2" ;;
    *) no "A1 the ranked head is not the named script (decoy head, the #466 confident-wrong answer): $head2" ;;
esac
for subj in document-remind.sh "the document-remind.sh script" '`document-remind.sh`'; do
    run bash --for="$subj" > "$T/a2.xml"
    if has "$T/a2.xml" '<named-file p="plugins/acme/scripts/document-remind.sh"'; then ok "A2 '$subj' serves the page"
    else no "A2 '$subj' does not serve the page"; fi
done

# ── B: the other languages ──────────────────────────────────────────────────────────────────────────────────────────────────
run py --for=sync_ledger > "$T/b1.xml"
if ! has "$T/b1.xml" 'reason="no_candidates"' && has "$T/b1.xml" '<named-file p="tools/sync_ledger.py"' && has "$T/b1.xml" "if __name__ == '__main__':"; then
    ok "B1 snake stem: not no_candidates; page with the __main__ block"
else no "B1 snake stem sync_ledger: no_candidates or no page"; fi
run py --for="what does sync_ledger.py do" > "$T/b2.xml"
if has "$T/b2.xml" '<named-file p="tools/sync_ledger.py"'; then ok "B2 'what does sync_ledger.py do' serves the page"
else no "B2 'what does sync_ledger.py do' serves no page"; fi
for spec in "rb sync_ledger bin/sync_ledger.rb" "rb sync_ledger.rb bin/sync_ledger.rb" "lua sync_ledger.lua scripts/sync_ledger.lua" \
            "js sync-ledger scripts/sync-ledger.js" "ts sync-ledger.ts scripts/sync-ledger.ts"; do
    set -- $spec
    run "$1" --for="$2" > "$T/b3.xml"
    if has "$T/b3.xml" "<named-file p=\"$3\"" && has "$T/b3.xml" '<top l="'; then ok "B3 $1 '$2' serves $3 with top-level text"
    else no "B3 $1 '$2' serves no page (or no top-level text) for $3"; fi
done

# ── C: ambiguity and the dotted near miss ───────────────────────────────────────────────────────────────────────────────────
run py --for=util.py > "$T/c1.xml"
if has "$T/c1.xml" '<named-files n="util.py" total="2">' && has "$T/c1.xml" '<f p="pkg_a/util.py"' && has "$T/c1.xml" '<f p="pkg_b/util.py"' \
   && ! has "$T/c1.xml" '<named-file ' && ! has "$T/c1.xml" 'file subject:'; then
    ok "C1 ambiguous basename: both listed, none picked, no lift"
else no "C1 ambiguous basename util.py: not listed as two, or one was picked"; fi
run ts2 --for=Location.go > "$T/c2.xml"
if ! has "$T/c2.xml" '<named-file' && ! has "$T/c2.xml" '<named-files' && grep -qE '<d [^>]*n="(Location\.)?go"' "$T/c2.xml"; then
    ok "C2 Location.go (no such file) keeps its dotted reading: method go served, no page"
else no "C2 Location.go: a page appeared or the method go is not served"; fi

# ── D: a directory ──────────────────────────────────────────────────────────────────────────────────────────────────────────
run go --for="cmd/syncledger package" > "$T/d1.xml"
if has "$T/d1.xml" '<named-dir p="cmd/syncledger" files="1">' && has "$T/d1.xml" '<named-file p="cmd/syncledger/main.go"'; then
    ok "D1 directory anchor: named-dir with main.go's page"
else no "D1 directory anchor cmd/syncledger: no named-dir page"; fi

# ── E: near misses that must NOT serve a page ───────────────────────────────────────────────────────────────────────────────
run py --for="where STATE used in sync_ledger.py is defined" > "$T/e1.xml"
if ! has "$T/e1.xml" '<named-file'; then ok "E1 a file named as context carries no page"
else no "E1 a file named as context got a page"; fi
run py --for=run_all > "$T/e2.xml"
if ! has "$T/e2.xml" '<named-file' && ! has "$T/e2.xml" 'file subject:'; then ok "E2 a stem that is a symbol's name stays a name"
else no "E2 run_all (a function's name) was read as a file stem"; fi

# ── F / R / K: honesty ─────────────────────────────────────────────────────────────────────────────────────────────────────
if grep -qE '<s t="fn" n="unused_helper" l="7" e="8" in="0">' "$T/b1.xml" && grep -qE '<s t="fn" n="emit" [^>]*by="[^"]*tools/test_sync_ledger.py' "$T/b1.xml" \
   && has "$T/b1.xml" 'NOT unused'; then
    ok "F1 in=0 on the uncalled def, by= names the caller's file, the clause hedges in=0"
else no "F1 in=/by= rows or the in=0 hedge missing"; fi
if ! has "$T/a1.xml" 'AKIAABCDEFGHIJKLMNOP' && has "$T/a1.xml" 'TOKEN='; then ok "R1 a secret in the top-level text is redacted"
else no "R1 the AKIA key reached the answer (or the line is missing)"; fi
run long --for=run-deploy.sh > "$T/k1.xml"
shown="$( python3 - "$T/k1.xml" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
print(sum(c.count("\n") + 1 for c in re.findall(r'<top l="\d+" e="\d+"><!\[CDATA\[(.*?)\]\]></top>', s, re.S)))
PY
)"
if [ "$shown" -le 40 ] && grep -qE '<top_cut top_lines="121" shown="40" rest="41-121"/>' "$T/k1.xml"; then ok "K1 the 40-line cap discloses top_cut (shown $shown)"
else no "K1 top-level cap: shown=$shown lines or no top_cut disclosure"; fi

# ── N: postures without the page ────────────────────────────────────────────────────────────────────────────────────────────
( cd "$T/py" && RIPWIRE_NO_FILE_PAGE=1 HOME="$H" TMPDIR="$T/" "$BIN" "$T/py" --no-cache --for=sync_ledger < /dev/null 2>/dev/null ) > "$T/n1.xml"
run py --for=sync_ledger --json > "$T/n2.json"
if ! has "$T/n1.xml" '<named-file' && ! has "$T/n1.xml" 'named-file p=' && ! has "$T/n2.json" 'named-file'; then ok "N1 no page with RIPWIRE_NO_FILE_PAGE=1 nor under --json"
else no "N1 a page rode under the kill switch or --json"; fi

# ── L: the clause defines what the page carries ─────────────────────────────────────────────────────────────────────────────
run py --for=sync_ledger --legend=full > "$T/l1.xml"
for f in "$T/b1.xml" "$T/l1.xml" "$T/c1.xml" "$T/d1.xml" "$T/k1.xml"; do
    if python3 - "$f" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r"(; named-file p= .*?(?:capped=1 cut|the list was cut))", s, re.S)
if not m: print("    no file-page clause in", sys.argv[1]); sys.exit(1)
clause = m.group(1)
a, b = s.find("<named-"), s.rfind("</named-")
if a < 0 or b < 0: print("    no page in", sys.argv[1]); sys.exit(1)
page = re.sub(r"<!\[CDATA\[.*?\]\]>", "", s[a:b], flags=re.S)
miss = set()
for el in re.findall(r"<(named-file|named-files|named-dir|top_cut|top|s|f)\b([^>]*)>", page):
    for a in re.findall(r" ([a-z_]+)=\"", el[1]):
        if not re.search(r"(?<![a-z_])" + a + r"=", clause): miss.add(el[0] + "." + a)
if miss: print("    undefined:", sorted(miss)); sys.exit(1)
PY
    then ok "L1 the clause defines every page attribute ($(basename "$f"))"
    else no "L1 the clause misses a page attribute ($(basename "$f"))"; fi
done

# ── X: determinism, well-formedness, no "--" in the legend ─────────────────────────────────────────────────────────────────
run bash --for=document-remind > "$T/x1.xml"
if cmp -s "$T/a1.xml" "$T/x1.xml"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    bad=0
    for f in "$T"/a1.xml "$T"/b1.xml "$T"/c1.xml "$T"/d1.xml "$T"/k1.xml "$T"/l1.xml; do xmllint --noout "$f" 2>/dev/null || { bad=1; echo "    not well-formed: $f"; }; done
    [ "$bad" -eq 0 ] && ok "X2 xmllint well-formed" || no "X2 an answer is not well-formed"
else echo "  SKIP  X2 xmllint not installed"; fi
if python3 - "$T/l1.xml" "$T/b1.xml" <<'PY'
import re, sys
for f in sys.argv[1:]:
    for c in re.findall(r"<!--(.*?)-->", open(f).read(), re.S):
        if "--" in c: sys.exit(1)
PY
then ok "X3 no '--' inside a legend comment"; else no "X3 a legend comment holds '--'"; fi

[ "$fail" -eq 0 ] && echo "forfileanchorcheck: PASS" || echo "forfileanchorcheck: FAIL"
exit "$fail"
