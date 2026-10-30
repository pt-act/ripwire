### Fixed — a `--path` chain stitched from calls bound by name alone is no longer printed as the plain answer

`--path` (and MCP `path_between`, and the `<graph_verb>` block of a `--for` path subject) printed the shortest chain the search
found, `reachable="1"`, even when several of its hops were `via="name"` calls whose receiver nothing proves. On Django,
`--path=QuerySet.__iter__,SQLCompiler.execute_sql` answered a 12-hop chain with 5 such hops through the prefetch code, and
`--path=Model.save,SQLInsertCompiler.execute_sql` a 5-hop chain through `QuerySet.aggregate`: neither is how the call gets there,
and nothing on the answer said so. One shared verdict now judges the chain a single-pair answer prints:

- 2 or more by-name hops, and a chain over proven call edges only exists between the same definitions: that proven chain is
  printed instead, with `route_hedged="proven-preferred" route_len= route_by_name=` describing the shorter by-name one.
- 2 or more by-name hops and no proven chain: printed as before, hedged on the root with
  `route_hedged="name-stitched" route_by_name="K" route_cands="P"` (K by-name hops, P the product of their same-named candidates).
- 4 or more by-name hops with more than one candidate chain and no proven chain: refused as the answer (3 is only hedged: on CPython, `--path=asyncio.run,Handle._run` is a true chain with 3 by-name hops). The root says
  `reachable="0" hops="0" route_hedged="not-proven" route_len="N"`, no hop rows print, and `next=` follows `from=`'s callees. The
  legend says reachable=0 here means "not proven", never "no route".

A chain with at most one by-name hop, and an answer listing several definition pairs, print exactly as before.
