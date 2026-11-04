#!/usr/bin/env bash
# mcptokencheck.sh — the gate for the --mcp-token argv-exposure warning (audit finding #7, Low).
#
# `--mcp-token=SECRET` puts the shared bearer in argv, where any local user can read it out of the process
# list for the life of the server. The safer channel (RIPWIRE_MCP_TOKEN) already existed; nothing steered
# operators to it. The remediation is a ONE-LINE stderr warning at HTTP startup when the token came from
# argv — not a refusal (the argv form keeps working) and not a change to authentication.
#
# ARMS
#   (a) ARGV TOKEN WARNS — `--mcp-token=SECRET` emits exactly ONE stderr line matching the pinned regex,
#       and the secret itself never appears in stderr or stdout. One line, once: a per-request warning
#       would be noise, and a warning that echoed the secret would be the leak it warns about.
#   (b) ENV TOKEN IS SILENT — `RIPWIRE_MCP_TOKEN=SECRET` with no argv token emits no warning line, and an
#       authenticated request still answers 200. The env channel is the recommended one; warning on it
#       would be wrong.
#   (c) AUTH UNCHANGED — with a token configured, a missing and a wrong Bearer still get 401. The warning
#       is a diagnostic, not a policy change.
#   (d) DOCS RECOMMEND THE ENV CHANNEL — the reference docs name RIPWIRE_MCP_TOKEN as the safer channel
#       AND state the exposure the warning is about. (The bare "docs mention RIPWIRE_MCP_TOKEN" assertion
#       is already true at the base commit — the string appears in the spliced --mcp-token help text — so
#       it cannot discriminate; this arm asserts the recommendation, which is what Phase 2 adds.)
#
# Usage: RIPWIRE_BIN=build/ripwire bash test/mcptokencheck.sh
# Exits non-zero on any failure. Registered in test/regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
SRV_PID=""
cleanup(){ [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the HTTP client"; exit 2; }
command -v curl    >/dev/null 2>&1 || { echo "curl required (present on macOS/Linux)"; exit 2; }

. "$ROOT/test/lib/gatehttp.sh"
GATEHTTP="$( gatehttp_install "$TMP" )" || { echo "could not write the shared HTTP client into $TMP"; exit 2; }

# A tiny fixture root: the listener pins one workspace at startup and warms its index before accepting.
WS="$TMP/ws"; mkdir -p "$WS"
printf 'int tokenFixture() { return 0; }\n' >"$WS/fixture.cpp"

PORT=$(( 20000 + ( $$ % 20000 ) ))
URL="http://127.0.0.1:$PORT/mcp"
MCP_ACCEPT='application/json, text/event-stream'
MCP_INIT='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"ripwire-test","version":"1.0"}}}'

# The pinned warning contract. Wording is the spec's; the gate owns the exact regex.
WARN_RE='ripwire: .*--mcp-token.*process list.*RIPWIRE_MCP_TOKEN'
SECRET='hunter2-argv-secret'

# start_server <out> <err> [env assignments…] -- [args…]
# Starts the listener, waits until it ANSWERS (gatehttp's waitServing), and leaves the pid in SRV_PID.
start_server(){
    local out="$1" err="$2"; shift 2
    local envs=()
    while [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    # `${envs[@]+"${envs[@]}"}` is the bash-3.2 guard: under `set -u` a bare `"${envs[@]}"` on an EMPTY
    # array dies with "envs[@]: unbound variable" (arms (a)/(c) pass no env). The dying background subshell
    # inherits the EXIT trap, its cleanup() deletes the shared $TMP, and every later arm then fails on
    # missing files — one root cause, four fail-lines. Inert on bash 5.
    env ${envs[@]+"${envs[@]}"} "$BIN" "$WS" --listen=127.0.0.1:"$PORT" "$@" >"$out" 2>"$err" &
    SRV_PID=$!
    if ! python3 "$GATEHTTP" wait "$PORT" "$SRV_PID" >"$TMP/why" 2>&1; then
        return 1
    fi
    return 0
}
stop_server(){ [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; SRV_PID=""; }

echo "mcptokencheck: BIN=$BIN"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (a) argv token warns once, and never echoes the secret ==="
# ═══════════════════════════════════════════════════════════════════════════
if start_server "$TMP/a.out" "$TMP/a.err" -- --mcp-token="$SECRET"; then
    warnCount="$( grep -cE "$WARN_RE" "$TMP/a.err" 2>/dev/null || true )"
    if [ "${warnCount:-0}" = "1" ]; then
        ok "(a) --mcp-token emits exactly one warning line"
    else
        no "(a) expected exactly 1 warning line, got ${warnCount:-0}: $( head -c 300 "$TMP/a.err" )"
    fi
    if grep -qF "$SECRET" "$TMP/a.err" "$TMP/a.out" 2>/dev/null; then
        no "(a) the secret appears in stderr/stdout — the warning leaked the token"
    else
        ok "(a) the secret never appears in stderr or stdout"
    fi
    stop_server
else
    no "(a) listener failed to start: $( cat "$TMP/why" 2>/dev/null ); stderr: $( head -3 "$TMP/a.err" 2>/dev/null )"
    stop_server
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (b) env token is silent and still authenticates ==="
# ═══════════════════════════════════════════════════════════════════════════
if start_server "$TMP/b.out" "$TMP/b.err" "RIPWIRE_MCP_TOKEN=$SECRET" --; then
    if grep -qE "$WARN_RE" "$TMP/b.err" 2>/dev/null; then
        no "(b) the env channel warned — it is the recommended channel: $( grep -E "$WARN_RE" "$TMP/b.err" | head -1 )"
    else
        ok "(b) RIPWIRE_MCP_TOKEN emits no warning"
    fi
    code="$( curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST "$URL" \
             -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json' \
             -H "Authorization: Bearer $SECRET" -d "$MCP_INIT" 2>/dev/null )"
    if [ "$code" = "200" ]; then ok "(b) the env token authenticates (200)"; else no "(b) env token got $code (expected 200)"; fi
    stop_server
else
    no "(b) listener failed to start: $( cat "$TMP/why" 2>/dev/null ); stderr: $( head -3 "$TMP/b.err" 2>/dev/null )"
    stop_server
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (c) authentication is unchanged: missing and wrong bearer still 401 ==="
# ═══════════════════════════════════════════════════════════════════════════
if start_server "$TMP/c.out" "$TMP/c.err" -- --mcp-token="$SECRET"; then
    miss="$( curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST "$URL" \
             -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json' -d "$MCP_INIT" 2>/dev/null )"
    wrong="$( curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST "$URL" \
              -H "Accept: $MCP_ACCEPT" -H 'Content-Type: application/json' \
              -H 'Authorization: Bearer WRONG' -d "$MCP_INIT" 2>/dev/null )"
    [ "$miss" = "401" ]  && ok "(c) missing bearer → 401"  || no "(c) missing bearer got $miss (expected 401)"
    [ "$wrong" = "401" ] && ok "(c) wrong bearer → 401"    || no "(c) wrong bearer got $wrong (expected 401)"
    stop_server
else
    no "(c) listener failed to start: $( cat "$TMP/why" 2>/dev/null )"
    stop_server
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (d) the reference docs recommend the env channel and name the exposure ==="
# ═══════════════════════════════════════════════════════════════════════════
DOCS="$ROOT/docs/COMMANDS.md"
if [ -f "$DOCS" ]; then
    grep -q 'RIPWIRE_MCP_TOKEN' "$DOCS" \
        && ok "(d) docs name RIPWIRE_MCP_TOKEN" \
        || no "(d) docs do not name RIPWIRE_MCP_TOKEN"
    # "process list" is the phrase the warning itself uses; a bare `ps ` matches "drops it" and friends.
    grep -qi 'process list' "$DOCS" \
        && ok "(d) docs state the argv exposure the warning is about" \
        || no "(d) docs do not state the process-list exposure"
else
    no "(d) no docs/COMMANDS.md at $DOCS"
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
