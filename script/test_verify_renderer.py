"""Release-tool regressions from the Sepolia verification failures."""

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

import verify_renderer
from record_deployment import deployment_path


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

    def test_versioned_record_preserves_original_manifest_name(self):
        self.assertEqual(str(deployment_path(11155111)), "deployments/11155111.json")
        self.assertEqual(str(deployment_path(11155111, "v2")), "deployments/11155111-v2.json")
        with self.assertRaisesRegex(ValueError, "invalid deployment label"):
            deployment_path(11155111, "../old")

    def test_public_deploy_rejects_invalid_label(self):
        result = self._wrapper_with_stub_git(DEPLOYMENT_LABEL="../old")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DEPLOYMENT_LABEL must contain", result.stderr)

    def test_versioned_deploy_preserves_old_record_and_broadcast(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "script/env").mkdir(parents=True)
            shutil.copy(pathlib.Path(__file__).parent / "deploy.sh", root / "script/deploy.sh")
            shutil.copy(pathlib.Path(__file__).parent / "env/sepolia.env", root / "script/env/sepolia.env")
            (root / "deployments").mkdir()
            (root / "deployments/11155111.json").write_text("old manifest")
            broadcast = root / "broadcast/Deploy.s.sol/11155111"
            broadcast.mkdir(parents=True)
            (broadcast / "run-latest.json").write_text("old broadcast")

            bin_dir = root / "bin"
            bin_dir.mkdir()
            stubs = {
                "git": '#!/bin/sh\nif [ "$1" = branch ]; then echo main; else echo /mock/git; fi\n',
                "cast": "#!/bin/sh\necho 11155111\n",
                "forge": '#!/bin/sh\nif [ "$1" = script ]; then echo "new broadcast" > broadcast/Deploy.s.sol/11155111/run-latest.json; fi\n',
                "python3": '#!/bin/sh\necho "new manifest" > "deployments/11155111-$6.json"\n',
            }
            for name, source in stubs.items():
                executable = bin_dir / name
                executable.write_text(source)
                executable.chmod(0o755)
            env = dict(
                os.environ,
                PATH=f"{bin_dir}:{os.environ['PATH']}",
                DEPLOYMENT_LABEL="v2",
                KEYSTORE_ACCOUNT="ripe0x",
            )
            env.pop("RPC_URL", None)
            env.pop("FOUNDRY_PROFILE", None)
            result = subprocess.run(
                ["bash", "script/deploy.sh", "sepolia"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / "deployments/11155111.json").read_text(), "old manifest")
            self.assertEqual((root / "deployments/11155111-v2.json").read_text(), "new manifest\n")
            self.assertEqual((broadcast / "run-before-v2.json").read_text(), "old broadcast")
            self.assertEqual((broadcast / "run-latest.json").read_text(), "new broadcast\n")

            # A failed attempt may leave no new run-latest; the archive still blocks a retry.
            (root / "deployments/11155111-v2.json").unlink()
            (broadcast / "run-latest.json").unlink()
            retry = subprocess.run(
                ["bash", "script/deploy.sh", "sepolia"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(retry.returncode, 0)
            self.assertIn("marks a prior deployment attempt", retry.stderr)
            self.assertFalse((broadcast / "run-latest.json").exists())

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
