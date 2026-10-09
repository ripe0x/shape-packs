"""Release-tool regressions from the Sepolia verification failures."""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

import verify_renderer


class VerificationInputTest(unittest.TestCase):
    def test_foundry_path_fields_never_reach_etherscan(self):
        build_input = {
            "version": "0.8.28",
            "language": "Solidity",
            "sources": {"src/Example.sol": {"content": "contract Example {}"}},
            "settings": {"optimizer": {"enabled": True, "runs": 20}},
            "allowPaths": ["/local/repository"],
            "basePath": "/local/repository",
            "includePaths": ["/local/repository/lib"],
        }
        submitted = json.loads(verify_renderer.standard_json_source(build_input))
        self.assertEqual(set(submitted), {"language", "sources", "settings"})

    def test_input_must_include_source_content(self):
        with self.assertRaisesRegex(RuntimeError, "self-contained"):
            verify_renderer.standard_json_source(
                {"language": "Solidity", "sources": {"src/Example.sol": {"urls": ["file.sol"]}}, "settings": {}}
            )

    def test_deploy_wrapper_cannot_use_forge_auto_verification(self):
        wrapper = (pathlib.Path(__file__).parent / "deploy.sh").read_text()
        self.assertNotIn("ARGS+=(--verify)", wrapper)

    def test_public_deploy_rejects_non_tenderly_rpc(self):
        result = self._wrapper_with_stub_git(RPC_URL="https://example.invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires Tenderly public RPC", result.stderr)

    def test_public_deploy_rejects_other_compiler_profile(self):
        result = self._wrapper_with_stub_git(FOUNDRY_PROFILE="testnet")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires FOUNDRY_PROFILE=default", result.stderr)

    def _wrapper_with_stub_git(self, **overrides):
        root = pathlib.Path(__file__).parent.parent
        with tempfile.TemporaryDirectory() as temp:
            git = pathlib.Path(temp) / "git"
            git.write_text(
                '#!/bin/sh\nif [ "$1" = branch ]; then echo main; else echo /mock/git; fi\n'
            )
            git.chmod(0o755)
            env = dict(os.environ, PATH=f"{temp}:{os.environ['PATH']}", DRY_RUN="1")
            env.pop("RPC_URL", None)
            env.pop("FOUNDRY_PROFILE", None)
            env.update(overrides)
            return subprocess.run(
                ["bash", "script/deploy.sh", "sepolia"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )


if __name__ == "__main__":
    unittest.main()
