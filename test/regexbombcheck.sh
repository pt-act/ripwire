#!/usr/bin/env bash
# regexbombcheck.sh — A4-F10 gate: a catastrophic-backtracking --regex pattern must produce the SAME,
# BOUNDED, named refusal on every platform — never a crash, and never an unbounded hang.
#
# WHAT THIS GATE USED TO ASSERT, AND WHY IT CHANGED (M2, 2026-08-01). The original contract was "degrade,
# don't die": `(a+)+b` over a long run of 'a' made std::sregex_iterator throw regex_error MID-MATCH,
# src/search.h caught it, skipped the file and kept going, so the run still exited 0 with well-formed XML
# and the rest of the candidate set still matched. That contract was true — but only on Apple libc++,
# whose backtracker gives up fast with regex_error(error_complexity). The header of this file said so in
# as many words, and treated it as the toolchain.
#
# The first real Linux run (Ubuntu 24.04, clang 18 + libstdc++) proved the assumption load-bearing:
#
#     $ ripwire test/regexbombfix --regex='(a+)+b' --no-prefilter --no-cache
#     … CPU-bound, still running at 560 s, killed by the harness
#
# libstdc++ has NO complexity budget. It never throws, so the catch that the whole "degrade" contract
# rested on is never reached: the process backtracks exponentially, unbounded. A user's pathological
# --regex does not degrade on Linux — it hangs the tool, and this gate reds by timeout.
#
# THE NEW CONTRACT — one verdict, both platforms, decided before either engine runs. Exactly the shape of
# the L5 escape fix in src/search.h: the pattern is screened STRUCTURALLY at the single chokepoint
# (regexCompileError), ahead of the compile probe and ahead of any scanning, and a nested-unbounded
# quantifier is REFUSED by name with a workaround. Refusal is a first-class outcome here, not a
# consolation prize: it is bounded, it is identical everywhere, it names what is wrong, and — unlike a
# silently skipped file — it can never be mistaken for a measurement.
#
# test/regexbombfix/ has:
#   bomb.md     — a long line of 4000 'a's, no 'b' — the catastrophic-backtracking bait for `(a+)+b`.
#                 (.md, not .txt — ripwire only ingests files with a recognized extension into ing.files,
#                 and grep only scans ingested files; .md has no tree-sitter grammar but its raw bytes are
#                 still stored for grep, which is all this fixture needs.)
#   normal.cpp  — two ordinary EASY (a+)+b matches ("aab", "aaab"). Under the new contract these are what
#                 the PRECISION arms below match with safe patterns, proving the guard refuses the bomb
#                 SHAPE and not the corpus.
#
# Arms: (1) the bomb battery is refused — exit 1, bounded time, named construct, no hits= on stdout;
#       (2) the refusal is structural — same verdict against a corpus with no bomb file in it at all;
#       (3) the precision battery is NOT refused — safe patterns still scan the same fixture at exit 0;
#       (4) determinism — stdout AND stderr byte-identical run to run;
#       (5) informational — the mid-match catch survives as belt-and-braces (a refusal by name since
#           src/regexguard.h; test/regexguardcheck.sh arm (b) asserts it on every entry point).
#       (6) regex-screen-hardening (M3, 2026-10): the OVERLAPPING-ALTERNATION battery — a DIFFERENT shape
#           than (1)'s nested quantifiers, judged on a repeated group's top-level branches instead of its
#           inner quantifiers. (a|a)+b and (a|aa)+b are exact-duplicate / prefix branches; (x|xy)+c$ the
#           same with a trailing anchor; (\w|\d)+$ two classes whose bytes intersect; (a|a*)+ a branch that
#           can match zero bytes on its own. (5) below narrows to the one named, disclosed scope boundary
#           M3 does NOT cover — a multi-byte literal compared against a class.
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/regexbombcheck.sh
# Exits non-zero on any failure. Does NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/regexbombfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/regexbombfix dir — fixture missing"; exit 2; }

echo "regexbombcheck: BIN=$BIN  CORPUS=test/regexbombfix"

# A refusal must be BOUNDED, and "bounded" is the half of this contract a Mac could not have caught: on
# libstdc++ the pre-fix binary is still backtracking after 560 s. Every bomb run below is wrapped in a
# hard wall-clock cap so a regression shows up as a FAILURE rather than as a hung suite. No external
# timeout(1) is assumed (it is not on a stock macOS): a background run plus a polling wait does the same
# job in portable POSIX shell.
capRun(){                        # capRun <seconds> <outfile> <errfile> <args…> -> echoes the exit status, or 'TIMEOUT'
    local capSeconds="$1" outPath="$2" errPath="$3"; shift 3
    "$BIN" "$@" >"$outPath" 2>"$errPath" &
    local runPid=$! waitedTenths=0 capTenths=$(( capSeconds * 10 ))
    while kill -0 "$runPid" 2>/dev/null; do
        [ "$waitedTenths" -ge "$capTenths" ] && { kill -9 "$runPid" 2>/dev/null; wait "$runPid" 2>/dev/null; echo TIMEOUT; return; }
        sleep 0.1; waitedTenths=$(( waitedTenths + 1 ))
    done
    wait "$runPid"; echo $?
}

# ── (1) the BOMB BATTERY: every nested-unbounded-quantifier shape must be refused, fast and by name ──────
#   (a+)+b     the classic, and the one the Linux smoke actually hung on
#   (a*)*b     the nullable-inner twin
#   (a+)*b     unbounded outer over unbounded inner, star flavour
#   (a{2,})+b  the counted-but-unbounded interval — {n,} is as unbounded as +
#   ((a+))+b   the inner repetition one group deeper than the outer quantifier
#   ((a)+)+b   the repetition is on the INNER GROUP, not on an atom inside it
#   (a+|b)+c   alternation is no defence when a branch repeats without bound
#   (a?)+b     M2-b — BOUNDED inner under an unbounded outer (see the block below)
#   (a{1,3})+b M2-b — the interval flavour of the same
#   ((a)?)+b   M2-b — the bounded repetition is ON the inner group, not on an atom inside it
#   (a{3})+b   M2-b — exact {n} is a quantifier too; deliberately in, see the block below
#
# ── M2-b (2026-08-01): TWO OF THESE ARMS USED TO BE "MUST STILL SCAN" CONTROLS ──────────────────────────
# `(a?)+b` and `(a{1,3})+b` were arms of the PRECISION battery below. The screen only refused an unbounded
# quantifier over a group that repeated WITHOUT bound inside it, on the reasoning that '?' and '{m,n}' are
# bounded and so cannot drive the blowup. That reasoning encoded libc++ behaviour. The re-smoke ran the
# gate's own control set on Ubuntu 24.04 / clang 18 / libstdc++ and BOTH controls HUNG — killed by this
# harness's wall-clock cap, exactly like the (a+)+b bomb they were supposed to contrast with. Bounded is
# not the same as unambiguous: '(a?)+' can split a run of 'a' in as many ways as '(a+)+' can, because the
# inner may also match EMPTY, and '(a{1,3})+' because the inner's width varies. On libc++ the same two
# patterns return in milliseconds (and '(a{1,3})+b' even trips the mid-match complexity degrade), which is
# why this repo shipped them as controls for as long as it only ever ran on a Mac.
#
# Cross-platform-identical behaviour is the standing law and it admits exactly one verdict per pattern, so
# the screen was WIDENED rather than the controls re-labelled per platform: an unbounded quantifier
# ('*', '+', '{n,}') applied to a group that contains ANY quantifier at all — '?', '{m,n}' and exact '{n}'
# included — is refused. Exact '{n}' is in on purpose: a fixed-count inner is only unambiguous when what it
# repeats is itself fixed-width, and '((ab|c){2})+d' is a genuine bomb that reading the quantifier alone
# cannot tell apart from '(a{3})+b'. A structural screen that must return the same verdict on two different
# backtrackers cannot make that call, so it refuses — bounded, named, with a workaround — rather than hand
# either engine a pattern one of them never comes back from.
bombCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 20 "$TMP/out" "$TMP/err" "$CORPUS" --regex="$pat" --no-prefilter --no-cache )"
    if [ "$rc" = TIMEOUT ]; then
        no "$label: still running after 20 s — the bomb was HANDED TO THE ENGINE (this is the Linux hang)"
        return
    fi
    [ "$rc" -ge 128 ] && { no "$label: CRASHED (signal death, exit $rc)"; return; }
    if [ "$rc" -eq 1 ]; then ok "$label: refused at exit 1 (bounded, no scan)"; else no "$label: exit $rc (expected 1)"; fi
    grep -q 'hits=' "$TMP/out" && no "$label: printed a hits= element — a scan happened" || ok "$label: no hits= element on stdout"
    if grep -qF -- "$pat" "$TMP/err"; then ok "$label: refusal names the pattern"; else no "$label: refusal does not name the pattern"; fi
    grep -qi 'backtrack' "$TMP/err" && ok "$label: refusal names the construct (catastrophic backtracking)" \
        || no "$label: refusal does not name the construct: $( head -c 200 "$TMP/err" )"
}

bombCase "(a+)+b"    '(a+)+b'
bombCase "(a*)*b"    '(a*)*b'
bombCase "(a+)*b"    '(a+)*b'
bombCase "(a{2,})+b" '(a{2,})+b'
bombCase "((a+))+b"  '((a+))+b'
bombCase "((a)+)+b"  '((a)+)+b'
bombCase "(a+|b)+c"  '(a+|b)+c'
bombCase "(a?)+b"    '(a?)+b'
bombCase "(a{1,3})+b" '(a{1,3})+b'
bombCase "((a)?)+b"  '((a)?)+b'
bombCase "(a{3})+b"  '(a{3})+b'
bombCase "(?:a+)+b"  '(?:a+)+b'

# ── (6) the OVERLAPPING-ALTERNATION battery (M3): a repeated group's top-level branches, not its inner
# quantifiers — none of these five carries a quantifier INSIDE any branch, so arm (1)'s M2 screen alone
# would admit all five; M3 judges the branches themselves. Live-measured before M3 existed: a 90-byte line
# built for (a|aa)+b was still running when a 10 s cap killed it (src/regexguard.h's catastrophicAlternationMessage
# carries the same measurement). bombCase() already structurally refuses at compile time, before any corpus
# content matters, so the existing fixture is enough — these never reach the engine at all now.
bombCase "(a|a)+b (exact-duplicate branches)"   '(a|a)+b'
bombCase "(a|aa)+b (prefix branches)"           '(a|aa)+b'
bombCase '(x|xy)+c$ (prefix, trailing anchor)'  '(x|xy)+c$'
bombCase '(\w|\d)+$ (intersecting classes)'     '(\w|\d)+$'
bombCase "(a|a*)+ (a branch matches empty)"     '(a|a*)+'

# The refusal must carry a WORKAROUND, not just a complaint — the L5 refusal set that bar and this one
# keeps it. (Checked once; the sentence is shared by every construct.)
"$BIN" "$CORPUS" --regex='(a+)+b' --no-cache >/dev/null 2>"$TMP/err"
grep -qi 'collapse\|bounded' "$TMP/err" && ok "refusal offers a workaround" \
    || no "refusal offers no workaround: $( head -c 300 "$TMP/err" )"

# ── (2) the refusal is STRUCTURAL, not corpus-triggered ─────────────────────────────────────────────────
# The old behaviour depended on reaching the bomb FILE: no long run of 'a' in the tree, no blowup, no
# degrade. The guard reads the pattern and nothing else, so the same verdict must come back from a corpus
# that contains no bait at all — this is what makes the outcome identical on every machine and every tree.
BENIGN="$TMP/benign"; mkdir -p "$BENIGN"; printf 'int quietFunction() { return 0; }\n' >"$BENIGN/quiet.cpp"
rc="$( capRun 20 "$TMP/out" "$TMP/err" "$BENIGN" --regex='(a+)+b' --no-cache )"
# same TIMEOUT-vs-verdict distinction as safeCase() above: a kill is not a corpus-dependence finding either.
if [ "$rc" = TIMEOUT ]; then
    no "corpus without bait: TIMEOUT/KILLED after 20s — not a verdict, the scan never finished"
else
    { [ "$rc" = 1 ] && [ -s "$TMP/err" ]; } \
        && ok "refused identically over a corpus with no bomb file (structural, not corpus-triggered)" \
        || no "corpus without bait: exit $rc — the verdict depends on the corpus"
fi

# ── (3) PRECISION: the guard must catch the nested-unbounded class and nothing wider ─────────────────────
# Over-refusal is the failure mode a structural guard invites. Each of these is quantifier-free inside its
# group, or unquantified on the outside, or BOUNDED on the outside, or has its '+' in a character class or
# behind a backslash — and every one of them must still SCAN.
#
# M2-b left this list SHORTER on one axis and longer on another. The two bounded-inner arms moved to the
# bomb battery (they hang libstdc++ — see the block above), and three arms were added to pin down what the
# widened screen must NOT touch: a non-capturing group, because '(?:' opens a group with a '?' that is a
# MODIFIER and not a quantifier and a screen reading it as one would refuse every '(?:abc)+' in the world;
# a BOUNDED outer quantifier over a group stuffed with unbounded ones, which is the refusal message's own
# suggested workaround and would be a self-contradiction to refuse; and a bounded inner under an
# UNQUANTIFIED outer, which proves the verdict turns on the outer quantifier and not on the inner.
safeCase(){
    local label="$1" pat="$2"
    local rc; rc="$( capRun 20 "$TMP/out" "$TMP/err" "$CORPUS" --regex="$pat" --no-cache )"
    # W1-V4 (2026-08-11): rc="TIMEOUT" is capRun's own sentinel for "still running after the cap, killed by
    # this harness" -- it is NOT an engine exit code, and it is emphatically not exit 0. Before this check the
    # fall-through below sent it straight to the else branch and printed "OVER-REFUSED: ... exit TIMEOUT",
    # asserting a refusal VERDICT that was never reached: the process never returned, it was SIGKILLed. A
    # killed/timed-out scan must report as TIMEOUT/KILLED and nothing else -- distinguish it before the verdict
    # check runs, the same way bombCase() already does two screens up.
    if [ "$rc" = TIMEOUT ]; then
        no "$label: TIMEOUT/KILLED after 20s — not a refusal verdict, the scan never finished (raise the harness budget or investigate a real hang, don't read this as over-refusal)"
        return
    fi
    { [ "$rc" = 0 ] && grep -q 'hits=' "$TMP/out"; } \
        && ok "not over-refused: $label still scans at exit 0" \
        || no "OVER-REFUSED: $label exit $rc — $( head -c 200 "$TMP/err" )"
}

safeCase "a+b (no group)"          'a+b'
safeCase "(a)+b (empty inner)"     '(a)+b'
safeCase "(abc)+ (literal group)"  '(abc)+'
safeCase "(a|b)+ (plain alt)"      '(a|b)+'
safeCase "[a+]+b ('+' in class)"   '[a+]+b'
safeCase "(a+)b (outer unquant.)"  '(a+)b'
safeCase "(a+)(b)+ (siblings)"     '(a+)(b)+'
safeCase "(?:abc)+ (non-capturing)" '(?:abc)+'
safeCase "(\s*\w+){1,20} (bounded outer)" '(\s*\w+){1,20}'
safeCase "(a?)b (bounded, outer unquant.)" '(a?)b'
safeCase "foo.*bar (spanning, no group)"  'foo.*bar'
safeCase "TODO|FIXME (top-level alt, unquantified)" 'TODO|FIXME'

# and the point of the fixture survives: a safe pattern still finds normal.cpp's ordinary matches while
# bomb.md sits in the very same candidate set, scanned harmlessly.
"$BIN" "$CORPUS" --regex='a+b' --no-prefilter --no-cache >"$TMP/normal" 2>/dev/null
grep -q 'normal.cpp' "$TMP/normal" \
    && ok "normal.cpp's matches still land with a safe pattern (bomb.md in the same candidate set)" \
    || { no "normal.cpp matches missing under a safe pattern"; head -40 "$TMP/normal"; }

if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/normal" 2>/dev/null; then ok "well-formed XML on the safe path"; else { no "malformed XML"; cat "$TMP/normal"; }; fi
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── (4) DETERMINISM — the refusal is a pure function of the pattern, so stderr too, not just stdout ──────
"$BIN" "$CORPUS" --regex='(a+)+b' --no-cache >"$TMP/d1" 2>"$TMP/e1"
"$BIN" "$CORPUS" --regex='(a+)+b' --no-cache >"$TMP/d2" 2>"$TMP/e2"
{ diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/e1" "$TMP/e2" >/dev/null; } \
    && ok "deterministic (two refusals byte-identical on stdout AND stderr)" || no "non-deterministic"
"$BIN" "$CORPUS" --regex='a+b' --no-prefilter --no-cache >"$TMP/s1" 2>/dev/null
"$BIN" "$CORPUS" --regex='a+b' --no-prefilter --no-cache >"$TMP/s2" 2>/dev/null
if diff -q "$TMP/s1" "$TMP/s2" >/dev/null; then ok "deterministic on the safe scanning path too"; else no "non-deterministic (safe path)"; fi

# ── (5) informational: the MID-MATCH catch survives as belt-and-braces for M3's disclosed residual gap ──
# M3 (src/regexguard.h) now refuses (a|a)+b structurally — arm (6) above asserts it, so it no longer
# exercises the mid-match catch at all. The one scope boundary M3 names but does not judge is a multi-byte
# literal compared against a class ('ab' vs '\w'): (ab|a\w)+c still passes every screen (neither branch
# carries a quantifier, so M2 is silent; 'ab' is two bytes so M3's FIRST-BYTE rule does not compare it
# against '\w' at all) while remaining exactly the same hazard — both branches consume the same bytes at
# every position in a run built from 'ab' pairs. A dedicated fixture is needed: the committed bomb.md/
# normal.cpp are pure 'a' runs, which this shape does not bite (neither branch of (ab|a\w) matches a lone
# 'a' unambiguously the way (a|aa) does). Catch around the match is NOT removed; it lives in
# src/regexguard.h now, and on libc++ it converts a mid-match error_complexity into a REFUSAL by name at
# exit 1 (it used to skip the file silently, leaving hits= a floor nothing disclosed). It stays
# informational HERE because on libstdc++ that error never arrives (the whole reason for the guard);
# test/regexguardcheck.sh arm (b) asserts the refusal on every platform through a fault switch.
ALTFIX="$TMP/altfix"; mkdir -p "$ALTFIX"
python3 -c "print('ab' * 60 + 'xc')" >"$ALTFIX/alt.md" 2>/dev/null \
    || awk 'BEGIN{s="";for(i=0;i<60;i++)s=s"ab";print s "xc"}' >"$ALTFIX/alt.md"
rc="$( capRun 30 "$TMP/out" "$TMP/err" "$ALTFIX" --regex='(ab|a\w)+c' --no-prefilter --no-cache )"
if [ "$rc" = TIMEOUT ]; then
    printf '  INFO  overlapping-alternation bomb (ab|a\\w)+c ran past 30 s — the one DISCLOSED gap in M3 (a\n'
    printf '        multi-byte literal against a class) on a libstdc++-shaped engine; src/regexguard.h names it\n'
elif grep -qi 'regex' "$TMP/err"; then
    ok "informational: mid-match catch still wired ($( grep -i regex "$TMP/err" | head -1 | head -c 160 ))"
else
    printf '  INFO  (ab|a\\w)+c completed at exit %s with no degrade alert (expected under NDEBUG, or if the\n' "$rc"
    printf '        engine simply matched it) — the belt-and-braces catch is not asserted, only kept\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
