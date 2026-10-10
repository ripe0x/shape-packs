#!/usr/bin/env bash
# Mint six sample packs in a fresh, labelled Sepolia collection from primary main.
set -euo pipefail

if [ "$#" -ne 1 ] || [[ ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
  echo "usage: script/mint_samples.sh <deployment-label>" >&2
  exit 1
fi
LABEL="$1"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$(git branch --show-current)" != "main" ] \
  || [ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
  echo "refusing: mint samples from the primary main checkout" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "refusing: mint samples from a clean checkout" >&2
  exit 1
fi

MANIFEST="deployments/11155111-${LABEL}.json"
[ -f "$MANIFEST" ] || { echo "refusing: missing $MANIFEST" >&2; exit 1; }
MANIFEST_VALUES="$(python3 - "$MANIFEST" <<'PY'
import json
import re
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
if data.get("chainId") != 11155111:
    raise SystemExit("refusing: manifest is not Sepolia")
values = [data.get(key) for key in ("shapes", "shapePacks", "deployer")]
if any(not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", value) for value in values):
    raise SystemExit("refusing: manifest has invalid addresses")
print("\t".join(values))
PY
)"
IFS=$'\t' read -r SHAPES PACKS EXPECTED_SIGNER <<< "$MANIFEST_VALUES"
export SHAPES PACKS EXPECTED_SIGNER

RPC_URL=https://gateway.tenderly.co/public/sepolia
if [ "$(cast chain-id --rpc-url "$RPC_URL")" != 11155111 ]; then
  echo "refusing: RPC is not Sepolia" >&2
  exit 1
fi
if [ "$(cast call "$PACKS" 'totalMinted()(uint256)' --rpc-url "$RPC_URL")" != 0 ]; then
  echo "refusing: collection is no longer empty; reconcile prior mints" >&2
  exit 1
fi

export FOUNDRY_PROFILE=default
ARGS=(script/MintSamples.s.sol --rpc-url "$RPC_URL" --gas-estimate-multiplier 1000)
if [ "${DRY_RUN:-0}" = 1 ]; then
  ARGS+=(--sender "$EXPECTED_SIGNER")
else
  BROADCAST=broadcast/MintSamples.s.sol/11155111/run-latest.json
  [ ! -e "$BROADCAST" ] || { echo "refusing: prior broadcast exists; inspect receipts before retrying" >&2; exit 1; }
  ARGS+=(--account ripe0x --broadcast --slow)
fi

# Sepolia execution can cost more gas than Foundry's local Cancun simulation predicts.
forge clean
forge script "${ARGS[@]}"
