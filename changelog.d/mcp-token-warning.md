### Security — `--mcp-token` warns that the bearer is visible in the process list

`--mcp-token=SECRET` puts the shared bearer in argv, where any local user can read it out of the process
list for the life of the server. The safer `RIPWIRE_MCP_TOKEN` channel already existed, but nothing steered
operators to it. An HTTP MCP startup whose token came from argv now prints one stderr line naming the
exposure and the recommended channel; the env channel stays silent, the argv form keeps working, and
authentication is unchanged (a missing or wrong Bearer still gets a 401). The token value is never printed.

The `--mcp-token` help entry now leads with the env channel and states the exposure, and its two spliced
descriptions — a pre-existing defect that read "mandatory for a non-loopback bind shared bearer token
gating every HTTP request" — are one sentence again. `test/mcptokencheck.sh` pins all four behaviours.
