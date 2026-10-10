"""Release-tool regressions from the Sepolia verification failures."""

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

import verify_renderer
from record_deployment import broadcast_path, deployment_path, save_new_file


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

    def test_public_deploy_rejects_dirty_main(self):
        result = self._wrapper_with_stub_git(FAKE_GIT_DIRTY="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("require a clean main checkout", result.stderr)

    def test_versioned_record_preserves_original_manifest_name(self):
        self.assertEqual(str(deployment_path(11155111)), "deployments/11155111.json")
        self.assertEqual(str(deployment_path(11155111, "v2")), "deployments/11155111-v2.json")
        self.assertEqual(str(broadcast_path(11155111, "v2")), "broadcast/Deploy.s.sol/11155111/snapshot-v2.json")
        with self.assertRaisesRegex(ValueError, "invalid deployment label"):
            deployment_path(11155111, "../old")
        with self.assertRaisesRegex(ValueError, "invalid deployment label"):
            deployment_path(11155111, "latest")

    def test_broadcast_snapshot_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temp:
            snapshot = pathlib.Path(temp) / "snapshot-v2.json"
            save_new_file(snapshot, b"first")
            with self.assertRaises(FileExistsError):
                save_new_file(snapshot, b"second")
            self.assertEqual(snapshot.read_bytes(), b"first")

    def test_public_deploy_rejects_invalid_label(self):
        result = self._wrapper_with_stub_git(DEPLOYMENT_LABEL="../old")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DEPLOYMENT_LABEL must contain", result.stderr)
        reserved = self._wrapper_with_stub_git(DEPLOYMENT_LABEL="latest")
        self.assertNotEqual(reserved.returncode, 0)
        self.assertIn("cannot be latest", reserved.stderr)

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
                "git": '#!/bin/sh\nif [ "$1" = branch ]; then echo main; elif [ "$1" = status ]; then :; else echo /mock/git; fi\n',
                "cast": "#!/bin/sh\necho 11155111\n",
                "forge": (
                    '#!/bin/sh\n'
                    'if [ "$1" = script ]; then\n'
                    '  echo "$*" >> forge.calls\n'
                    '  case " $* " in\n'
                    '    *" --broadcast "*) echo "new broadcast" > broadcast/Deploy.s.sol/11155111/run-latest.json ;;\n'
                    '    *) echo "Estimated amount required: 0.01 ETH" ;;\n'
                    '  esac\n'
                    'fi\n'
                ),
                "python3": '#!/bin/sh\ncp broadcast/Deploy.s.sol/11155111/run-latest.json "broadcast/Deploy.s.sol/11155111/snapshot-$6.json"\necho "new manifest" > "deployments/11155111-$6.json"\n',
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
            dry_env = dict(env, DRY_RUN="1")
            dry_env.pop("KEYSTORE_ACCOUNT")
            dry = subprocess.run(
                ["bash", "script/deploy.sh", "sepolia"],
                cwd=root,
                env=dry_env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(dry.returncode, 0, dry.stderr)
            self.assertIn("Estimated amount required: 0.01 ETH", dry.stdout)
            self.assertFalse((broadcast / "run-latest.json").read_text() == "new broadcast\n")
            result = subprocess.run(
                ["bash", "script/deploy.sh", "sepolia"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertLess(result.stdout.index("Estimated amount required"), result.stdout.index("keystore prompt follows"))
            calls = (root / "forge.calls").read_text().splitlines()
            self.assertIn("--sender 0xcb43078c32423f5348cab5885911c3b5fae217f9", calls[0])
            self.assertIn("--sender 0xcb43078c32423f5348cab5885911c3b5fae217f9", calls[1])
            self.assertNotIn("--account", calls[1])
            self.assertIn("--account ripe0x", calls[2])
            self.assertIn("--broadcast", calls[2])
            self.assertEqual((root / "deployments/11155111.json").read_text(), "old manifest")
            self.assertEqual((root / "deployments/11155111-v2.json").read_text(), "new manifest\n")
            self.assertEqual((broadcast / "run-before-v2.json").read_text(), "old broadcast")
            self.assertEqual((broadcast / "run-latest.json").read_text(), "new broadcast\n")
            self.assertEqual((broadcast / "snapshot-v2.json").read_text(), "new broadcast\n")

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
            self.assertIn("v2 marks a prior deployment attempt", retry.stderr)
            self.assertFalse((broadcast / "run-latest.json").exists())

    def test_mainnet_rehearses_without_keystore_and_requires_fee_output(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "script/env").mkdir(parents=True)
            shutil.copy(pathlib.Path(__file__).parent / "deploy.sh", root / "script/deploy.sh")
            shutil.copy(pathlib.Path(__file__).parent / "env/mainnet.env", root / "script/env/mainnet.env")
            bin_dir = root / "bin"
            bin_dir.mkdir()
            stubs = {
                "git": '#!/bin/sh\nif [ "$1" = branch ]; then echo main; elif [ "$1" = status ]; then :; else echo /mock/git; fi\n',
                "cast": "#!/bin/sh\necho 1\n",
                "forge": (
                    '#!/bin/sh\n'
                    'if [ "$1" = script ]; then\n'
                    '  echo "$*" >> forge.calls\n'
                    '  [ "${FAKE_NO_FEE:-0}" = 1 ] || echo "Estimated amount required: 0.1 ETH"\n'
                    'fi\n'
                ),
            }
            for name, source in stubs.items():
                executable = bin_dir / name
                executable.write_text(source)
                executable.chmod(0o755)
            env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", CONFIRM_MAINNET="yes", DRY_RUN="1")
            for key in ("PRIVATE_KEY", "KEYSTORE_ACCOUNT", "RPC_URL", "FOUNDRY_PROFILE"):
                env.pop(key, None)
            failed = subprocess.run(
                ["bash", "script/deploy.sh", "mainnet"],
                cwd=root, env=dict(env, FAKE_NO_FEE="1"), text=True, capture_output=True, check=False,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("refusing to request the keystore", failed.stderr)
            result = subprocess.run(
                ["bash", "script/deploy.sh", "mainnet"],
                cwd=root, env=env, text=True, capture_output=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Estimated amount required: 0.1 ETH", result.stdout)
            self.assertIn("admin=0xcb43078c32423f5348cab5885911c3b5fae217f9", result.stdout)
            for call in (root / "forge.calls").read_text().splitlines():
                self.assertIn("--sender 0xcb43078c32423f5348cab5885911c3b5fae217f9", call)
                self.assertNotIn("--account", call)
                self.assertNotIn("--broadcast", call)

    def _wrapper_with_stub_git(self, **overrides):
        root = pathlib.Path(__file__).parent.parent
        with tempfile.TemporaryDirectory() as temp:
            git = pathlib.Path(temp) / "git"
            git.write_text(
                '#!/bin/sh\nif [ "$1" = branch ]; then echo main; elif [ "$1" = status ]; then [ "${FAKE_GIT_DIRTY:-0}" = 1 ] && echo " M src/ShapePacks.sol"; else echo /mock/git; fi\n'
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
