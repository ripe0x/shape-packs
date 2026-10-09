#!/usr/bin/env python3
"""Verify a live renderer using the deployment script's full compiler input."""

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

from record_deployment import address, rpc


ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGETS = {
    "sepolia": (11155111, "https://gateway.tenderly.co/public/sepolia"),
    "mainnet": (1, "https://gateway.tenderly.co/public/mainnet"),
}
API_URL = "https://api.etherscan.io/v2/api"
CONTRACT_PATH = "src/ShapePackRenderer.sol"
CONTRACT_NAME = "ShapePackRenderer"


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


def prepare(chain_id, rpc_url):
    manifest = json.loads((ROOT / f"deployments/{chain_id}.json").read_text())
    if manifest["chainId"] != chain_id:
        raise RuntimeError("deployment manifest has the wrong chain")
    renderer = address(manifest["shapePackRenderer"])
    broadcast = json.loads((ROOT / f"broadcast/Deploy.s.sol/{chain_id}/run-latest.json").read_text())
    candidates = [t for t in broadcast["transactions"] if t["contractName"] == CONTRACT_NAME]
    if len(candidates) != 1:
        raise RuntimeError("broadcast must contain one renderer creation")
    creation = candidates[0]
    if address(creation["contractAddress"]) != renderer or creation["transactionType"] != "CREATE":
        raise RuntimeError("renderer creation does not match the manifest")

    if int(rpc(rpc_url, "eth_chainId", []), 16) != chain_id:
        raise RuntimeError("Tenderly RPC reports the wrong chain")
    transaction = rpc(rpc_url, "eth_getTransactionByHash", [creation["hash"]])
    receipt = rpc(rpc_url, "eth_getTransactionReceipt", [creation["hash"]])
    if not transaction or not receipt or int(receipt["status"], 16) != 1:
        raise RuntimeError("renderer creation is missing or failed onchain")
    if address(receipt["contractAddress"]) != renderer or transaction["to"] is not None:
        raise RuntimeError("onchain renderer creation does not match the manifest")
    creation_input = transaction["input"].lower()
    if creation_input != creation["transaction"]["input"].lower():
        raise RuntimeError("onchain creation input differs from the broadcast")
    if rpc(rpc_url, "eth_getCode", [renderer, "latest"]) == "0x":
        raise RuntimeError("renderer has no live code")

    env = dict(os.environ, FOUNDRY_PROFILE="default")
    subprocess.run(["forge", "clean"], cwd=ROOT, env=env, check=True)
    subprocess.run(
        ["forge", "build", "--build-info", "--quiet", "script/Deploy.s.sol"],
        cwd=ROOT,
        env=env,
        check=True,
    )
    matches = []
    for path in (ROOT / "out/build-info").glob("*.json"):
        build = json.loads(path.read_text())
        contract = build.get("output", {}).get("contracts", {}).get(CONTRACT_PATH, {}).get(CONTRACT_NAME)
        if contract:
            matches.append((build, contract))
    if len(matches) != 1:
        raise RuntimeError("expected one renderer build-info record")
    build, contract = matches[0]
    bytecode = contract["evm"]["bytecode"]["object"].lower().removeprefix("0x")
    expected_args = manifest["shapes"].lower().removeprefix("0x").rjust(64, "0")
    if creation_input != "0x" + bytecode + expected_args:
        raise RuntimeError("full build does not exactly match the onchain creation input")
    compiler = json.loads(contract["metadata"])["compiler"]["version"]
    if compiler != "0.8.28+commit.7893614a":
        raise RuntimeError(f"unexpected compiler version: {compiler}")
    source = json.dumps(build["input"], separators=(",", ":"))
    print(f"Matched live renderer creation at {renderer} ({len(bytecode) // 2} bytecode bytes).")
    return renderer, expected_args, compiler, source


def submit(chain_id, renderer, constructor_args, compiler, source, key):
    response = etherscan(
        chain_id,
        key,
        "verifysourcecode",
        {
            "contractaddress": renderer,
            "sourceCode": source,
            "contractname": f"{CONTRACT_PATH}:{CONTRACT_NAME}",
            "compilerversion": f"v{compiler}",
            "codeformat": "solidity-standard-json-input",
            "constructorArguments": constructor_args,
            "licenseType": "3",  # MIT
        },
    )
    if response.get("status") != "1":
        raise RuntimeError(f"Etherscan rejected submission: {response.get('result')}")
    guid = response["result"]
    print(f"Etherscan submission GUID: {guid}")
    for _ in range(20):
        time.sleep(5)
        result = etherscan(chain_id, key, "checkverifystatus", {"guid": guid})
        if result.get("status") == "1":
            print(f"Etherscan: {result.get('result')}")
            return
        if "pending" not in str(result.get("result", "")).lower():
            raise RuntimeError(f"Etherscan verification failed: {result.get('result')}")
    raise RuntimeError(f"verification is still pending; check GUID {guid} on Etherscan")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("--submit", action="store_true", help="submit the checked input to Etherscan")
    args = parser.parse_args()
    require_primary_main()
    chain_id, rpc_url = TARGETS[args.target]
    renderer, constructor_args, compiler, source = prepare(chain_id, rpc_url)
    if args.submit:
        key = os.environ.get("ETHERSCAN_API_KEY")
        if not key:
            raise RuntimeError("ETHERSCAN_API_KEY is required for --submit")
        submit(chain_id, renderer, constructor_args, compiler, source, key)
    else:
        print("Preflight passed. Rerun with --submit to publish source on Etherscan.")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"renderer verification stopped: {exc}", file=sys.stderr)
        sys.exit(1)
