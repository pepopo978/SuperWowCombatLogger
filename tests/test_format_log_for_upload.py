#!/usr/bin/env python3

import importlib.util
import pathlib
import tempfile
import unittest


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "format_log_for_upload.py"


def load_module():
    spec = importlib.util.spec_from_file_location("format_log_for_upload", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class FormatLogForUploadTests(unittest.TestCase):
    def test_restored_apostrophized_consume_names_normalize_to_legacy_output(self):
        module = load_module()

        contents = "\n".join(
            [
                "3/11 20:00:00.000  Chef uses Kreeg's Stout Beatdown.",
                "3/11 20:00:01.000  Chef uses Medivh's Merlot.",
                "3/11 20:00:02.000  Chef uses Medivh's Merlot Blue.",
                "3/11 20:00:03.000  Chef uses Danonzo's Tel'Abim Delight.",
                "3/11 20:00:04.000  Chef uses Danonzo's Tel'Abim Medley.",
                "3/11 20:00:05.000  Chef uses Danonzo's Tel'Abim Surprise.",
                "3/11 20:00:06.000  Chef uses Graccu's Homemade Meat Pie.",
                "3/11 20:00:07.000  Chef uses Graccu's Mince Meat Fruitcake.",
                "",
            ]
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            log_path = pathlib.Path(tmpdir) / "WoWCombatLog.txt"
            log_path.write_text(contents, encoding="utf-8")

            module.replace_instances([("3/11 19:59:59.000", "Chef")], str(log_path))

            rewritten = log_path.read_text(encoding="utf-8")

        self.assertIn("Kreegs Stout Beatdown", rewritten)
        self.assertIn("Medivhs Merlot", rewritten)
        self.assertIn("Medivhs Merlot Blue", rewritten)
        self.assertIn("Danonzos Tel'Abim Delight", rewritten)
        self.assertIn("Danonzos Tel'Abim Medley", rewritten)
        self.assertIn("Danonzos Tel'Abim Surprise", rewritten)
        self.assertIn("Graccus Homemade Meat Pie", rewritten)
        self.assertIn("Graccus Mince Meat Fruitcake", rewritten)


if __name__ == "__main__":
    unittest.main()
