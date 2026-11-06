### Added — an integration gate replays the 2026-09-14 audit's five attacks against the real binary, both transports

The five audit fixes each had their own unit gate, and each passed. What none of them could say is whether the
five compose in one binary — whether the regex screen still refuses on the CLI while the MCP `grep` verb stays
literal-only, whether the edit pin still refuses on the tiers it pins, whether the atomic publish still ignores a
planted temp name, whether hostile git paths still attribute to their author, and whether each transport still
refuses past **its own** bound and then keeps serving. `test/auditregresscheck.sh` asserts exactly that and
nothing else, against a purpose-built adversarial fixture (`test/fixtures/audit-reef/`): a one-line 128 KB
ReDoS subject, a real minimal OOXML zip (a fake `PK\x03\x04` header would prove nothing about the markitdown
branch), and a hostile git repo built at run time — a committed name containing `|`, a space or a newline does
not survive every checkout path.

Eight rows, one per (attack, transport) pair, each `repelled` and each required to carry the exact shape the
repaired acceptance criteria name — the structural-screen lead-in `refused, nothing was scanned:` (not the
`refused, no hit is reported` abandonment, and not the exit status, which reads identically for both). The
report is emitted as real CSV and parsed as real CSV: one field legitimately contains `", "`, and an
`awk -F', '` column counter reports that row as malformed when it is exactly right.

**Four things the gate deliberately does not assert, each disclosed in its own header.** It does not assert a
regex *refusal* over MCP — no MCP verb takes a regex at all (`grep` is literal-only), so the HTTP leg asserts
transport safety instead: a bomb-shaped pattern answers a structured empty and a **positive control** proves
the tree really was scanned, because without one an empty answer is indistinguishable from a dead scan. It does
not arm the bare-stdio edit escape: `ripwire --mcp` with no startup root runs the `assumedRoot` tier, which the
edit pin's own gate never enters, so an off-workspace edit succeeds there — a real finding, filed, and a
proposed spec, but a permanently red row is an issue tracker and not a gate. It does not conflate the two caps:
HTTP refuses past 8 MiB and stdio past 32 MiB, so a 9 MiB *stdio* line is inside the shipped bound, served,
and correctly not an attack row. And it does not assert "pargates green" from inside itself, because
`test/pargates.py` runs every top-level `test/*.sh` — a gate that ran it would re-enter without bound; the two
legs a gate cannot own (pargates, ASan) are SKIPped with the reason named rather than pretended.

The gate is test-only: no `src/` file changes, and the five fixes it pins are unchanged by it.
