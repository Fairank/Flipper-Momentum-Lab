"""Keep pre-fusion wire identifiers stable across schema/submodule updates."""

import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProtocolCompatibilityTests(unittest.TestCase):
    def test_original_wire_fields_are_preserved_and_new_tags_do_not_collide(self):
        old = json.loads(
            (Path(__file__).parent / "fixtures/protobuf_legacy_tags.json").read_text()
        )
        text = (ROOT / "assets/protobuf_overrides/flipper.proto").read_text()
        content = text.split("oneof content {", 1)[1].split("}", 1)[0]
        fields = [
            (t, n, int(i))
            for t, n, i in re.findall(r"([.\w]+)\s+(\w+)\s*=\s*(\d+)\s*;", content)
        ]
        self.assertEqual(len(fields), len({n for _, n, _ in fields}))
        self.assertEqual(len(fields), len({i for _, _, i in fields}))
        for field in old["content"]:
            self.assertIn((field["type"], field["name"], field["tag"]), fields)
        legacy_names = {f["name"] for f in old["content"]}
        additions = [(t, n, i) for t, n, i in fields if n not in legacy_names]
        self.assertEqual({i for _, _, i in additions}, set(range(76, 91)))
        self.assertTrue(
            all(n.startswith(("network_", "gps_")) for _, n, _ in additions)
        )

    def test_ascii_extension_stays_available(self):
        text = (ROOT / "assets/protobuf_overrides/gui.proto").read_text()
        self.assertIn("message SendAsciiEventRequest", text)
        main = (ROOT / "assets/protobuf_overrides/flipper.proto").read_text()
        self.assertRegex(
            main,
            r"\.PB_Gui\.SendAsciiEventRequest\s+gui_send_ascii_event_request\s*=\s*100;",
        )


if __name__ == "__main__":
    unittest.main()
