#!/usr/bin/env python3
"""Record a deployment only after its receipts and live constructor state are verified."""

import json
import os
import pathlib
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request


def address(value):
    number = int(value, 16)
    if number == 0 or number >= 2**160:
        raise ValueError(f"invalid address: {value}")
    return f"0x{number:040x}"


def deployment_path(chain_id, label=""):
    if label and not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]*", label):
        raise ValueError("invalid deployment label")
    return pathlib.Path(f"deployments/{chain_id}{'-' + label if label else ''}.json")


def broadcast_path(chain_id, label=""):
    deployment_path(chain_id, label)  # Apply the same path-safety check.
    name = f"run-{label}.json" if label else "run-latest.json"
    return pathlib.Path(f"broadcast/Deploy.s.sol/{chain_id}/{name}")


def save_new_file(path, content):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile("wb", dir=path.parent, prefix=".deployment-", delete=False) as out:
            temporary = out.name
            out.write(content)
        os.link(temporary, path)  # Never replace an existing record or broadcast snapshot.
    finally:
        if temporary:
            os.unlink(temporary)


def rpc(url, method, params):
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, payload, {"Content-Type": "application/json"})
            with urllib.request.urlopen(request, timeout=30) as response:
                result = json.load(response)
            if "error" in result:
                if result["error"].get("code") == -32005 and attempt < 3:
                    time.sleep(2**attempt)
                    continue
                raise RuntimeError(f"{method}: {result['error'].get('message', 'RPC error')}")
            return result["result"]
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 502, 503, 504) or attempt == 3:
                raise
            time.sleep(2**attempt)
    raise RuntimeError(f"{method}: RPC retries exhausted")


def call_uint(url, target, selector):
    result = rpc(url, "eth_call", [{"to": target, "data": selector}, "latest"])
    if len(result) != 66:
        raise RuntimeError(f"{target} returned malformed data for {selector}")
    return int(result, 16)


def call_address(url, target, selector):
    return address(hex(call_uint(url, target, selector)))


def record(chain_id, url, shapes_input, admin_input, label=""):
    path = deployment_path(chain_id, label)
    if int(rpc(url, "eth_chainId", []), 16) != chain_id:
        raise RuntimeError("RPC chain id changed during deployment")

    artifact = broadcast_path(chain_id)
    broadcast = artifact.read_bytes()
    transactions = json.loads(broadcast)["transactions"]
    by_name = {item["contractName"]: item for item in transactions}
    if len(transactions) != 2 or set(by_name) != {"ShapePackRenderer", "ShapePacks"}:
        raise RuntimeError("broadcast does not contain exactly the two expected creations")

    renderer = address(by_name["ShapePackRenderer"]["contractAddress"])
    packs = address(by_name["ShapePacks"]["contractAddress"])
    shapes = address(shapes_input)
    senders = {address(item["transaction"]["from"]) for item in transactions}
    if len(senders) != 1 or any(item["transactionType"] != "CREATE" for item in transactions):
        raise RuntimeError("broadcast has an unexpected sender or transaction type")
    deployer = senders.pop()
    admin = address(admin_input) if admin_input else deployer

    # Foundry's artifact can associate hashes with the wrong creation when transactions fail.
    # Match receipts to contracts by their actual onchain contractAddress instead.
    receipts = {}
    for item in transactions:
        receipt = rpc(url, "eth_getTransactionReceipt", [item["hash"]])
        if not receipt or int(receipt["status"], 16) != 1:
            raise RuntimeError(f"transaction {item['hash']} is missing or failed")
        if address(receipt["from"]) != deployer:
            raise RuntimeError("receipt sender mismatch")
        deployed = address(receipt["contractAddress"])
        receipts[deployed] = receipt
    if set(receipts) != {renderer, packs}:
        raise RuntimeError("receipt contract addresses do not match the broadcast")

    for target in (renderer, packs):
        if rpc(url, "eth_getCode", [target, "latest"]) == "0x":
            raise RuntimeError(f"{target} has no deployed code")

    if call_address(url, renderer, "0x184f9654") != shapes:  # shapes()
        raise RuntimeError("renderer.shapes mismatch")
    if call_address(url, packs, "0x184f9654") != shapes:
        raise RuntimeError("packs.shapes mismatch")
    if call_address(url, packs, "0x8ada6b0f") != renderer:  # renderer()
        raise RuntimeError("packs.renderer mismatch")
    if call_address(url, packs, "0xf851a440") != admin:  # admin()
        raise RuntimeError("packs.admin mismatch")
    min_value = call_uint(url, packs, "0xecf0ec2f")  # MIN_PACK_VALUE()
    if min_value != 3 * call_uint(url, shapes, "0x907af6c0"):  # unit()
        raise RuntimeError("MIN_PACK_VALUE mismatch")

    manifest = {
        "chainId": chain_id,
        "shapes": shapes,
        "shapePacks": packs,
        "shapePackRenderer": renderer,
        "admin": admin,
        "minPackValueWei": str(min_value),
        "deployer": deployer,
        "blockNumber": max(int(item["blockNumber"], 16) for item in receipts.values()),
    }
    if label:
        save_new_file(broadcast_path(chain_id, label), broadcast)
    save_new_file(path, (json.dumps(manifest, indent=2) + "\n").encode())


if __name__ == "__main__":
    try:
        record(int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else "")
    except (IndexError, KeyError, OSError, RuntimeError, ValueError) as exc:
        print(f"deployment readback failed: {exc}", file=sys.stderr)
        sys.exit(1)
