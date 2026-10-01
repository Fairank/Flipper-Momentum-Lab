# Companion schema compatibility

The `assets/protobuf` submodule follows DarkFlippers' public schema at
`05d4dc1e11dc3d22c453e13edebf82ff5ead5bd2` (protocol 0.29).

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
