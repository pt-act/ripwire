#!/usr/bin/env bash
# pathroutecheck.sh — a reached --path chain stitched from calls bound by name alone is hedged, refused, or replaced by a proven
# chain; never printed as the plain reachable answer (src/pathroute.h pathRouteVerdict, PATH-ROUTE v2).
#
# THE DEFECT. shortestPathAny is a plain BFS over every out-edge, proven and by-name alike. On LD-2 django-06 it printed
# reachable=1 hops=12 with 5 via="name" hops through the prefetch code (the wrong branch), and nothing on the root said the chain
# was name-stitched: an agent trusts it.
#
# THE CONTRACT (one predicate, both transports):
#   >= 2 by-name hops and a proven-only chain exists  -> the proven chain prints, route_hedged="proven-preferred"
#   >= 2 by-name hops, no proven chain                -> printed, route_hedged="name-stitched" route_by_name= route_cands=
#   >= 4 by-name hops, route_cands > 1, no proven one -> refused: reachable="0" hops="0" route_hedged="not-proven", no hop rows,
#                                                        next="--callees=<from>"
#   0..1 by-name hop, or cands=1 everywhere            -> unchanged (no route_hedged=)
#
# ARMS
#   (R) refuse: start_entry -> o.s1 -> o.s2 -> o.s3 -> sink, every hop by name over two same-named classes: refused, no decoy row.
#   (P) proven-preferred: a 3-hop by-name shortcut beside a 6-hop proven chain: the proven chain prints, no via=name row.
#   (H) hedge: two by-name hops (cands 2): printed whole, route_hedged="name-stitched" route_by_name="2".
#   (N1) near miss: one by-name hop among proven ones: no route_hedged=.
#   (N2) near miss: four by-name hops each with ONE candidate (cands=1): hedged, never refused.
#   (N3) near miss: three by-name hops with cands=2 each (the LARGE-DEV cpython-02 shape, a TRUE chain): hedged, never refused.
#   (L) the --legend=full clause rides exactly when route_hedged= does; every answer parses (xmllint when present).
#   (M) MCP path_between: the same verdict attrs and the same rows as the CLI on R, P, H.
#   (F) --for "<path subject>": the <graph_verb> block carries the same verdict as the CLI on R.
#
# Usage: test/pathroutecheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "pathroutecheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

mkdir -p "$TMP/r" "$TMP/p" "$TMP/h" "$TMP/n1" "$TMP/n2" "$TMP/n3" "$TMP/home"
# (R) every hop by name, each name defined by two classes (cands=2 per hop)
cat > "$TMP/r/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.s2(o)
    def s2(self, o):
        return o.s3(o)
    def s3(self, o):
        return o.sink_call(o)

class Beta:
    def s1(self, o):
        return 0
    def s2(self, o):
        return 0
    def s3(self, o):
        return 0

class Decoy:
    def sink_call(self, o):
        return 1

class Sink:
    def sink_call(self, o):
        return 2

def start_entry(o):
    return o.s1(o)
EOF
# (P) the by-name shortcut start_entry -> o.s1 -> o.s2 -> o.fin beside a proven 6-hop chain start_entry -> a1 -> a2 -> a3 -> a4 -> Sink.go -> Sink.fin (proven: a constructed receiver, self)
cat > "$TMP/p/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.s2(o)
    def s2(self, o):
        return o.fin(o)

class Beta:
    def s1(self, o):
        return 0
    def s2(self, o):
        return 0

class Sink:
    def go(self, o):
        return self.fin(o)
    def fin(self, o):
        return 3

class Decoy:
    def fin(self, o):
        return 4

def a4(o):
    s = Sink()
    return s.go(o)
def a3(o):
    return a4(o)
def a2(o):
    return a3(o)
def a1(o):
    return a2(o)

def start_entry(o):
    a1(o)
    return o.s1(o)
EOF
# (H) two by-name hops
cat > "$TMP/h/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.finish(o)

class Beta:
    def s1(self, o):
        return 0

class Sink:
    def finish(self, o):
        return 1

class Decoy:
    def finish(self, o):
        return 2

def start_entry(o):
    return o.s1(o)
EOF
# (N1) one by-name hop among proven ones
cat > "$TMP/n1/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return leaf(o)

class Beta:
    def s1(self, o):
        return 0

def leaf(o):
    return 1

def mid(o):
    return o.s1(o)

def start_entry(o):
    return mid(o)
EOF
# (N2) four by-name hops, each name defined once (cands=1)
cat > "$TMP/n2/m.py" <<'EOF'
class Alpha:
    def u1(self, o):
        return o.u2(o)
    def u2(self, o):
        return o.u3(o)

class Gamma:
    def u3(self, o):
        return o.u4(o)

class Delta:
    def u4(self, o):
        return 1

def start_entry(o):
    return o.u1(o)
EOF

# (N3) three by-name hops, cands=2 each: Alpha.s1 -> o.s2 -> o.sink_call
cat > "$TMP/n3/m.py" <<'EOF'
class Alpha:
    def s1(self, o):
        return o.s2(o)
    def s2(self, o):
        return o.sink_call(o)

class Beta:
    def s1(self, o):
        return 0
    def s2(self, o):
        return 0

class Decoy:
    def sink_call(self, o):
        return 1

class Sink:
    def sink_call(self, o):
        return 2

def start_entry(o):
    return o.s1(o)
EOF

run(){ local d=$1; shift; ( cd "$TMP/$d" || exit 1; env -u RIPWIRE_LEGEND HOME="$TMP/home" "$BIN" "$TMP/$d" --no-cache "$@" < /dev/null 2>/dev/null ); }
attr(){ python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<path [^>]*>",t); a=re.search(r"\s"+sys.argv[1]+r"=\"([^\"]*)\"",m.group(0)) if m else None; print(a.group(1) if a else "-")' "$1"; }
rows(){ python3 -c 'import re,sys; t=sys.stdin.read(); print(" ".join(re.findall(r"<s [^>]*n=\"([^\"]*)\"",t)))'; }

# (R)
R="$( run r --path=start_entry,Sink.sink_call )"
if [ "$( attr reachable <<<"$R" )" = 0 ] && [ "$( attr route_hedged <<<"$R" )" = not-proven ] && [ "$( attr route_by_name <<<"$R" )" -ge 3 ] 2>/dev/null \
   && [ -z "$( rows <<<"$R" )" ] && [ "$( attr next <<<"$R" )" != - ] && [ "$( attr next <<<"$R" | cut -c1-10 )" = --callees= ]; then
    ok "(R) a 4-hop by-name chain is refused: reachable=0 route_hedged=not-proven, no hop rows, next=--callees"
else
    no "(R) refuse: $( grep -o '<path [^>]*>' <<<"$R" ) rows=[$( rows <<<"$R" )]"
fi
if grep -q 'Decoy' <<<"$R"; then no "(R) the decoy rides in the answer"; else ok "(R) no decoy row"; fi
# (P)
P="$( run p --path=start_entry,Sink.fin )"
if [ "$( attr route_hedged <<<"$P" )" = proven-preferred ] && [ "$( attr reachable <<<"$P" )" = 1 ] && [ "$( attr hops <<<"$P" )" = 6 ] && ! grep -q 'via="name"' <<<"$P"; then
    ok "(P) the proven 6-hop chain prints over the by-name shortcut (route_hedged=proven-preferred)"
else
    no "(P) proven-preferred: $( grep -o '<path [^>]*>' <<<"$P" ) rows=[$( rows <<<"$P" )]"
fi
# (H)
H="$( run h --path=start_entry,Sink.finish )"
if [ "$( attr route_hedged <<<"$H" )" = name-stitched ] && [ "$( attr route_by_name <<<"$H" )" = 2 ] && [ "$( attr reachable <<<"$H" )" = 1 ] && [ "$( attr hops <<<"$H" )" = 2 ]; then
    ok "(H) a 2-hop by-name chain prints hedged (route_hedged=name-stitched route_by_name=2)"
else
    no "(H) hedge: $( grep -o '<path [^>]*>' <<<"$H" )"
fi
# (N1)
N1="$( run n1 --path=start_entry,leaf )"
if [ "$( attr reachable <<<"$N1" )" = 1 ] && [ "$( attr route_hedged <<<"$N1" )" = - ]; then ok "(N1) one by-name hop: no route_hedged="; else no "(N1) $( grep -o '<path [^>]*>' <<<"$N1" )"; fi
# (N2)
N2="$( run n2 --path=start_entry,Delta.u4 )"
if [ "$( attr reachable <<<"$N2" )" = 1 ] && [ "$( attr route_cands <<<"$N2" )" = 1 ] && [ "$( attr route_hedged <<<"$N2" )" = name-stitched ]; then
    ok "(N2) four by-name hops with one candidate each: hedged, never refused"
else
    no "(N2) $( grep -o '<path [^>]*>' <<<"$N2" )"
fi
# (N3)
N3="$( run n3 --path=start_entry,Sink.sink_call )"
if [ "$( attr reachable <<<"$N3" )" = 1 ] && [ "$( attr route_by_name <<<"$N3" )" = 3 ] && [ "$( attr route_hedged <<<"$N3" )" = name-stitched ]; then
    ok "(N3) three by-name hops with two candidates each: hedged and printed, never refused"
else
    no "(N3) $( grep -o '<path [^>]*>' <<<"$N3" )"
fi
# (L)
fullof(){ case $1 in
    R) run r --legend=full --path=start_entry,Sink.sink_call;;
    P) run p --legend=full --path=start_entry,Sink.fin;;
    H) run h --legend=full --path=start_entry,Sink.finish;;
    *) run n1 --legend=full --path=start_entry,leaf;;
    esac; }
for a in R P H N1; do
    full="$( fullof "$a" )"
    if grep -q 'route_hedged=' <<<"$full"; then
        if python3 -c 'import re,sys; sys.exit(0 if any("route_hedged=" in c for c in re.findall(r"<!--(.*?)-->",sys.stdin.read(),re.S)) else 1)' <<<"$full"; then ok "(L) $a: the legend clause rides with route_hedged="; else no "(L) $a: route_hedged= without its legend clause"; fi
    else
        if grep -q 'route_hedged' <<<"$full"; then no "(L) $a: legend clause without the attribute"; else ok "(L) $a: no attribute, no clause"; fi
    fi
    if command -v xmllint >/dev/null 2>&1; then
        if printf '<r>%s</r>' "$full" | xmllint --noout - 2>/dev/null; then ok "(L) $a parses"; else no "(L) $a: xmllint"; fi
    fi
done
# (M) MCP path_between: same verdict and rows
mcp(){ local d=$1 f=$2 t=$3; printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"g","version":"0"}}}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"path_between\",\"arguments\":{\"path\":\"$TMP/$d\",\"from\":\"$f\",\"to\":\"$t\"}}}" \
    | ( cd "$TMP/$d" || exit 1; HOME="$TMP/home" "$BIN" --mcp --mcp-legend=inline 2>/dev/null ) | python3 -c 'import json,sys
for l in sys.stdin:
    try: m=json.loads(l)
    except Exception: continue
    if m.get("id")==2: print("".join(c.get("text","") for c in m.get("result",{}).get("content",[])))'; }
for a in R P H; do
    if [ "$a" = R ]; then cli="$R"; m="$( mcp r start_entry Sink.sink_call )"
    elif [ "$a" = P ]; then cli="$P"; m="$( mcp p start_entry Sink.fin )"
    else cli="$H"; m="$( mcp h start_entry Sink.finish )"; fi
    if [ -z "$m" ]; then no "(M) $a: no MCP answer"; continue; fi
    if [ "$( attr route_hedged <<<"$m" )" = "$( attr route_hedged <<<"$cli" )" ] && [ "$( attr reachable <<<"$m" )" = "$( attr reachable <<<"$cli" )" ] \
       && [ "$( attr route_by_name <<<"$m" )" = "$( attr route_by_name <<<"$cli" )" ] && [ "$( rows <<<"$m" )" = "$( rows <<<"$cli" )" ]; then
        ok "(M) $a: path_between carries the CLI's verdict and rows"
    else
        no "(M) $a: MCP $( grep -o '<path [^>]*>' <<<"$m" | head -1 ) vs CLI $( grep -o '<path [^>]*>' <<<"$cli" )"
    fi
done
# (F) --for graph_verb block
F="$( run r '--for=path from start_entry to Sink.sink_call' )"
blk="$( python3 -c 'import re,sys; t=sys.stdin.read(); m=re.search(r"<graph_verb[^>]*>.*?</graph_verb>",t,re.S); print(m.group(0) if m else "")' <<<"$F" )"
if [ -z "$blk" ]; then
    no "(F) no <graph_verb> block on the --for path subject"
elif [ "$( attr route_hedged <<<"$blk" )" = not-proven ] && [ -z "$( rows <<<"$blk" )" ]; then
    ok "(F) the --for <graph_verb> block refuses the same chain"
else
    no "(F) $( grep -o '<path [^>]*>' <<<"$blk" )"
fi
[ "$fail" = 0 ] && echo "pathroutecheck: PASS" || echo "pathroutecheck: FAIL"
exit "$fail"
