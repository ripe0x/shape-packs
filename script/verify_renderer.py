#!/usr/bin/env python3
"""Verify both live contracts using the deployment script's full compiler input."""

import argparse
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from record_deployment import address, broadcast_path, deployment_path, rpc


ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = {
    "sepolia": (11155111, "https://gateway.tenderly.co/public/sepolia"),
    "mainnet": (1, "https://gateway.tenderly.co/public/mainnet"),
}
API_URL = "https://api.etherscan.io/v2/api"
CONTRACTS = (
    ("ShapePackRenderer", "src/ShapePackRenderer.sol", "shapePackRenderer", ("shapes",)),
    ("ShapePacks", "src/ShapePacks.sol", "shapePacks", ("shapes", "shapePackRenderer", "admin")),
)
STANDARD_JSON_KEYS = ("language", "sources", "settings")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def require_primary_main():
    if git("branch", "--show-current") != "main" or git(
        "rev-parse", "--path-format=absolute", "--git-dir"
    ) != git("rev-parse", "--path-format=absolute", "--git-common-dir"):
        raise RuntimeError("verification must run from the primary main checkout")


def etherscan(chain_id, key, action, fields):
    query = urllib.parse.urlencode(
        {"chainid": chain_id, "module": "contract", "action": action, "apikey": key}
    )
    url = f"{API_URL}?{query}"
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    request = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Etherscan returned HTTP {exc.code}") from None
    except urllib.error.URLError:
        raise RuntimeError("could not reach Etherscan") from None


def standard_json_source(build_input):
    # Foundry build info also carries CLI path options; those are not Standard JSON keys.
    compiler_input = {key: build_input[key] for key in STANDARD_JSON_KEYS}
    if compiler_input["language"] != "Solidity" or not compiler_input["sources"] or not all(
        set(source) == {"content"} for source in compiler_input["sources"].values()
    ):
        raise RuntimeError("compiler input is not self-contained Solidity Standard JSON")
    return json.dumps(compiler_input, separators=(",", ":"))


def prepare(chain_id, rpc_url, label=""):
    manifest = json.loads((ROOT / deployment_path(chain_id, label)).read_text())
    if manifest["chainId"] != chain_id:
        raise RuntimeError("deployment manifest has the wrong chain")
    broadcast = json.loads((ROOT / broadcast_path(chain_id, label)).read_text())
    transactions = broadcast["transactions"]
    if len(transactions) != len(CONTRACTS) or {t["contractName"] for t in transactions} != {
        name for name, _, _, _ in CONTRACTS
    }:
        raise RuntimeError("broadcast does not contain exactly the expected creations")
    by_name = {t["contractName"]: t for t in transactions}

    if int(rpc(rpc_url, "eth_chainId", []), 16) != chain_id:
        raise RuntimeError("Tenderly RPC reports the wrong chain")

    env = dict(os.environ, FOUNDRY_PROFILE="default")
    subprocess.run(["forge", "clean"], cwd=ROOT, env=env, check=True)
    subprocess.run(
        ["forge", "build", "--build-info", "--quiet", "script/Deploy.s.sol"],
        cwd=ROOT,
        env=env,
        check=True,
    )
    builds = []
    for path in (ROOT / "out/build-info").glob("*.json"):
        builds.append(json.loads(path.read_text()))
    if len(builds) != 1:
        raise RuntimeError("expected one deployment build-info record")
    build = builds[0]
    source = standard_json_source(build["input"])

    prepared = []
    for name, path, manifest_key, argument_keys in CONTRACTS:
        creation = by_name[name]
        target = address(manifest[manifest_key])
        if address(creation["contractAddress"]) != target or creation["transactionType"] != "CREATE":
            raise RuntimeError(f"{name} creation does not match the manifest")
        transaction = rpc(rpc_url, "eth_getTransactionByHash", [creation["hash"]])
        receipt = rpc(rpc_url, "eth_getTransactionReceipt", [creation["hash"]])
        if not transaction or not receipt or int(receipt["status"], 16) != 1:
            raise RuntimeError(f"{name} creation is missing or failed onchain")
        if address(receipt["contractAddress"]) != target or transaction["to"] is not None:
            raise RuntimeError(f"onchain {name} creation does not match the manifest")
        creation_input = transaction["input"].lower()
        if creation_input != creation["transaction"]["input"].lower():
            raise RuntimeError(f"onchain {name} creation input differs from the broadcast")
        if rpc(rpc_url, "eth_getCode", [target, "latest"]) == "0x":
            raise RuntimeError(f"{name} has no live code")

        contract = build["output"]["contracts"][path][name]
        bytecode = contract["evm"]["bytecode"]["object"].lower().removeprefix("0x")
        constructor_args = "".join(address(manifest[key])[2:].rjust(64, "0") for key in argument_keys)
        if creation_input != "0x" + bytecode + constructor_args:
            raise RuntimeError(f"full build does not exactly match the onchain {name} creation")
        compiler = json.loads(contract["metadata"])["compiler"]["version"]
        if compiler != "0.8.28+commit.7893614a":
            raise RuntimeError(f"unexpected {name} compiler version: {compiler}")
        print(f"Matched live {name} creation at {target} ({len(bytecode) // 2} bytecode bytes).")
        prepared.append((name, path, target, constructor_args, compiler, source))
    return prepared


def submit(chain_id, name, path, target, constructor_args, compiler, source, key):
    response = etherscan(
        chain_id,
        key,
        "verifysourcecode",
        {
            "contractaddress": target,
            "sourceCode": source,
            "contractname": f"{path}:{name}",
            "compilerversion": f"v{compiler}",
            "codeformat": "solidity-standard-json-input",
            "constructorArguments": constructor_args,
            "licenseType": "3",  # MIT
        },
    )
    if response.get("status") != "1":
        if "already verified" in str(response.get("result", "")).lower():
            print(f"Etherscan: {name} already verified")
            return
        raise RuntimeError(f"Etherscan rejected submission: {response.get('result')}")
    guid = response["result"]
    print(f"{name} Etherscan submission GUID: {guid}")
    for _ in range(20):
        time.sleep(5)
        result = etherscan(chain_id, key, "checkverifystatus", {"guid": guid})
        if result.get("status") == "1":
            print(f"Etherscan {name}: {result.get('result')}")
            return
        if "pending" not in str(result.get("result", "")).lower():
            raise RuntimeError(f"Etherscan verification failed: {result.get('result')}")
    raise RuntimeError(f"verification is still pending; check GUID {guid} on Etherscan")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("--label", default="", help="deployment generation, for example v2")
    parser.add_argument("--submit", action="store_true", help="submit the checked input to Etherscan")
    args = parser.parse_args()
    require_primary_main()
    chain_id, rpc_url = TARGETS[args.target]
    prepared = prepare(chain_id, rpc_url, args.label)
    if args.submit:
        key = os.environ.get("ETHERSCAN_API_KEY")
        if not key:
            raise RuntimeError("ETHERSCAN_API_KEY is required for --submit")
        for name, path, target, constructor_args, compiler, source in prepared:
            submit(chain_id, name, path, target, constructor_args, compiler, source, key)
    else:
        print("Both preflights passed. Rerun with --submit to publish source on Etherscan.")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"source verification stopped: {exc}", file=sys.stderr)
        sys.exit(1)
