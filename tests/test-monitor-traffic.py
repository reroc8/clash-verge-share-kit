"""Deterministic accounting tests; all inputs are local fixtures, not a live core."""

import contextlib
import csv
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("traffic", ROOT / "scripts" / "monitor-traffic.py")
traffic = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(traffic)
MB = traffic.MB


def conn(ident, up=0, down=0, process="Alpha", chains=None, provider=""):
    return {"id": ident, "upload": up, "download": down, "metadata": {"process": process},
            "chains": ["US-A", "AI"] if chains is None else chains,
            "providerChains": [provider, ""]}


class TrafficTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="clash-accounting-test-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.snap, self.state, self.total, self.log, self.proxies, self.providers = [
            root / name for name in ("snapshot.json", "state.json", "totals.json", "log.csv", "proxies.json", "providers.json")
        ]
        self.write(self.proxies, {"proxies": {"US-A": {"type": "Http"}, "Local": {"type": "Direct"}}})
        self.write(self.providers, {"providers": {}})
        self.log.write_text(",".join(traffic.CSV_FIELDS) + "\n", encoding="utf-8")

    @staticmethod
    def write(path, value):
        path.write_text(json.dumps(value), encoding="utf-8")

    def sample(self, rows):
        self.write(self.snap, {"connections": rows})
        with contextlib.redirect_stdout(io.StringIO()):
            traffic.sample(self.snap, self.state, self.total, self.log, "2026-11-01 00:00:00", self.proxies, self.providers)

    def rows(self):
        with self.log.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))

    def totals(self):
        return json.loads(self.total.read_text(encoding="utf-8"))

    def test_first_sample_is_baseline(self):
        self.sample([conn("old", 100 * MB, 200 * MB)])
        self.assertEqual(self.rows(), [])
        self.sample([conn("old", 105 * MB, 202 * MB)])
        self.assertEqual(self.totals()["proxy"]["Alpha"], [5 * MB, 2 * MB])

    def test_closed_connection_cannot_cancel_surviving_increment(self):
        self.sample([conn("closed", 100 * MB), conn("live")])
        self.sample([conn("live", 20 * MB)])
        self.assertEqual(self.totals()["proxy"]["Alpha"], [20 * MB, 0])
        self.assertEqual(self.rows()[0]["upload_delta_mb"], "20.000000")

    def test_new_connection_and_new_process_are_counted(self):
        self.sample([conn("old", 100 * MB)])
        self.sample([conn("new", 4 * MB), conn("new-process", down=3 * MB, process="Beta")])
        self.assertEqual(self.totals()["proxy"], {"Alpha": [4 * MB, 0], "Beta": [0, 3 * MB]})

    def test_empty_snapshot_does_not_reset_session(self):
        self.sample([])
        self.sample([conn("first", MB)])
        self.sample(None)
        self.sample([conn("second", 2 * MB)])
        self.assertEqual(self.totals()["proxy"]["Alpha"], [3 * MB, 0])

    def test_repeated_snapshot_does_not_double_count(self):
        self.sample([])
        self.sample([conn("new", MB)])
        self.sample([conn("new", MB)])
        self.assertEqual(len(self.rows()), 1)
        self.assertEqual(self.totals()["proxy"]["Alpha"], [MB, 0])

    def test_counter_rollback_is_not_negative(self):
        self.sample([conn("same", 10 * MB)])
        self.sample([conn("same", MB)])
        self.assertEqual(self.rows(), [])
        self.sample([conn("same", 2 * MB)])
        self.assertEqual(self.totals()["proxy"]["Alpha"], [MB, 0])

    def test_routes_do_not_mix_for_the_same_process(self):
        self.sample([])
        self.sample([conn("proxy", MB), conn("direct", 2 * MB, chains=["DIRECT", "AI"]),
                     conn("alias", 3 * MB, chains=["Local", "Proxies"]),
                     conn("unknown", 4 * MB, chains=[]), conn("missing", 5 * MB, chains=["unlisted"])])
        self.assertEqual(self.totals(), {
            "proxy": {"Alpha": [MB, 0]}, "direct": {"Alpha": [5 * MB, 0]},
            "unknown": {"Alpha": [9 * MB, 0]}
        })

    def test_group_name_does_not_define_the_actual_outbound(self):
        self.sample([])
        self.sample([conn("actual-proxy", MB, chains=["US-A", "DIRECT"])])
        self.assertEqual(self.rows()[0]["route"], "proxy")

    def test_provider_qualified_names_do_not_collide(self):
        self.write(self.providers, {"providers": {
            "airport": {"proxies": [{"name": "Local", "type": "Socks5"}]},
            "direct-provider": {"proxies": [{"name": "US-A", "type": "Direct"}]}
        }})
        self.sample([])
        self.sample([conn("proxy", MB, chains=["Local"], provider="airport"),
                     conn("direct", 2 * MB, chains=["US-A"], provider="direct-provider")])
        self.assertEqual(self.totals(), {"proxy": {"Alpha": [MB, 0]}, "direct": {"Alpha": [2 * MB, 0]}})

    def test_missing_type_metadata_stays_unknown(self):
        self.sample([])
        self.proxies.write_text("broken JSON", encoding="utf-8")
        self.providers.unlink()
        self.sample([conn("unknown", MB), conn("direct", MB, chains=["DIRECT"])])
        self.assertEqual(self.totals(), {"unknown": {"Alpha": [MB, 0]}, "direct": {"Alpha": [MB, 0]}})

    def test_direct_adapter_with_custom_dialer_stays_unknown(self):
        self.write(self.proxies, {"proxies": {"Local": {"type": "Direct", "dialer-proxy": "US-A"}}})
        self.sample([])
        self.sample([conn("chain", MB, chains=["Local"])])
        self.assertEqual(self.rows()[0]["route"], "unknown")

    def test_small_increments_accumulate_as_integer_bytes(self):
        self.sample([conn("tiny")])
        for count in range(1, 21):
            self.sample([conn("tiny", count, count * 2)])
        self.assertEqual(self.totals()["proxy"]["Alpha"], [20, 40])

    def test_csv_escapes_process_names(self):
        self.sample([])
        self.sample([conn("quoted", MB, process='App, "Helper"')])
        self.assertEqual(self.rows()[0]["process"], 'App, "Helper"')

    def test_malformed_snapshot_does_not_overwrite_baseline(self):
        self.sample([conn("alive", MB)])
        baseline = self.state.read_bytes()
        for rows in ([{"upload": 1, "download": 2}], [conn("duplicate"), conn("duplicate")]):
            with self.assertRaises(ValueError):
                self.sample(rows)
            self.assertEqual(self.state.read_bytes(), baseline)
        self.sample([conn("alive", 2 * MB)])
        self.assertEqual(self.totals()["proxy"]["Alpha"], [MB, 0])

    def test_report_keeps_route_labels_and_measurement_boundary(self):
        self.sample([])
        self.sample([conn("proxy", MB), conn("direct", MB, chains=["DIRECT"]), conn("unknown", MB, chains=[])])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            traffic.report(self.total)
        for label in ("代理", "直连", "未知", "非机场账单"):
            self.assertIn(label, output.getvalue())


if __name__ == "__main__":
    unittest.main()
