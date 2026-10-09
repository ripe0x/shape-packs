"""The manifest must reflect mined contracts, including when artifact hashes are misordered."""

import importlib.util
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "script" / "record_deployment.py"
SPEC = importlib.util.spec_from_file_location("record_deployment", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

RENDERER = "0x" + "11" * 20
PACKS = "0x" + "22" * 20
SHAPES = "0x" + "33" * 20
DEPLOYER = "0x" + "44" * 20


class RecordDeploymentTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.previous_cwd = os.getcwd()
        os.chdir(self.directory.name)
        pathlib.Path("broadcast/Deploy.s.sol/11155111").mkdir(parents=True)
        pathlib.Path("deployments").mkdir()
        transactions = [
            {"contractName": "ShapePackRenderer", "contractAddress": RENDERER,
             "transactionType": "CREATE", "hash": "0xaaa", "transaction": {"from": DEPLOYER}},
            {"contractName": "ShapePacks", "contractAddress": PACKS,
             "transactionType": "CREATE", "hash": "0xbbb", "transaction": {"from": DEPLOYER}},
        ]
        pathlib.Path("broadcast/Deploy.s.sol/11155111/run-latest.json").write_text(
            json.dumps({"transactions": transactions})
        )

    def tearDown(self):
        os.chdir(self.previous_cwd)
        self.directory.cleanup()

    def rpc(self, _url, method, params):
        if method == "eth_chainId":
            return hex(11155111)
        if method == "eth_getTransactionReceipt":
            # The hashes are intentionally attached to the wrong creation in the artifact.
            deployed = PACKS if params[0] == "0xaaa" else RENDERER
            return {"status": "0x1", "from": DEPLOYER, "contractAddress": deployed,
                    "blockNumber": "0x11" if deployed == PACKS else "0x10"}
        if method == "eth_getCode":
            return "0x6000"
        if method == "eth_call":
            target, selector = params[0]["to"], params[0]["data"]
            answers = {
                (RENDERER, "0x184f9654"): int(SHAPES, 16),
                (PACKS, "0x184f9654"): int(SHAPES, 16),
                (PACKS, "0x8ada6b0f"): int(RENDERER, 16),
                (PACKS, "0xf851a440"): int(DEPLOYER, 16),
                (PACKS, "0xecf0ec2f"): 300,
                (SHAPES, "0x907af6c0"): 100,
            }
            return f"0x{answers[(target, selector)]:064x}"
        self.fail(f"unexpected RPC method: {method}")

    def test_records_only_mined_addresses_and_live_state(self):
        with patch.object(MODULE, "rpc", side_effect=self.rpc):
            MODULE.record(11155111, "http://example.invalid", SHAPES, "")
        manifest = json.loads(pathlib.Path("deployments/11155111.json").read_text())
        self.assertEqual(manifest["shapePackRenderer"], RENDERER)
        self.assertEqual(manifest["shapePacks"], PACKS)
        self.assertEqual(manifest["minPackValueWei"], "300")
        self.assertEqual(manifest["blockNumber"], 17)

    def test_failed_receipt_does_not_write_manifest(self):
        def failed_rpc(url, method, params):
            result = self.rpc(url, method, params)
            if method == "eth_getTransactionReceipt" and params[0] == "0xaaa":
                result["status"] = "0x0"
            return result

        with patch.object(MODULE, "rpc", side_effect=failed_rpc):
            with self.assertRaisesRegex(RuntimeError, "failed"):
                MODULE.record(11155111, "http://example.invalid", SHAPES, "")
        self.assertFalse(pathlib.Path("deployments/11155111.json").exists())


if __name__ == "__main__":
    unittest.main()
