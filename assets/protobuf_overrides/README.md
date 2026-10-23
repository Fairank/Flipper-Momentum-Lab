# Companion schema compatibility

The `assets/protobuf` submodule follows DarkFlippers' public schema at
`d827357e8bc3dc68d73158998e9fa52509f30836` (protocol 0.30).

Protocol version metadata comes from the first release header in the pinned
Changelog, including untagged releases. The build does not fetch tags or report
the nearest older Git tag. Malformed or missing release headers stop the build.

These two source overlays preserve Momentum's ASCII keyboard extension while
adding the upstream GPS and network message families:

- `flipper.proto`: DarkFlippers' file plus `gui_send_ascii_event_request = 100`.
- `gui.proto`: Next-Flip's file at `ea4f185f5eaa265955c520eae2832887ee6aa5e4`.

All 73 pre-existing content tags (including Empty and StopSession) retain their
names, types and numbers. The 15
new companion messages use the upstream numbers 76–90. No existing message is
renumbered. The build picks one source per basename and searches the overlays
first when resolving imports.

Public sources: <https://github.com/DarkFlippers/flipperzero-protobuf> and
<https://github.com/Next-Flip/flipperzero-protobuf>. Upstream authorship is retained.
When updating the submodule, compare both overlays and rerun the protocol
compatibility tests. A compiled firmware service does not by itself establish
that a connected phone implements GPS or internet proxying.
