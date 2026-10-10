#!/usr/bin/env bash
# Mint the six Sepolia v3 sample packs from the primary main checkout.
set -euo pipefail

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

RPC_URL=https://gateway.tenderly.co/public/sepolia
PACKS=0xd1cfc13abcbb370d381ac192aeb6f2e1b414022a
if [ "$(cast chain-id --rpc-url "$RPC_URL")" != 11155111 ]; then
  echo "refusing: RPC is not Sepolia" >&2
  exit 1
fi
if [ "$(cast call "$PACKS" 'totalMinted()(uint256)' --rpc-url "$RPC_URL")" != 0 ]; then
  echo "refusing: v3 collection is no longer empty; reconcile prior mints" >&2
  exit 1
fi

export FOUNDRY_PROFILE=default
ARGS=(script/MintV3Samples.s.sol --rpc-url "$RPC_URL" --gas-estimate-multiplier 1000)
if [ "${DRY_RUN:-0}" = 1 ]; then
  ARGS+=(--sender 0xcb43078c32423f5348cab5885911c3b5fae217f9)
else
  ARGS+=(--account ripe0x --broadcast --slow)
fi

# Foundry's Cancun simulation understates Sepolia's live execution gas. Replaying the first
# failed mint through Tenderly estimated 1.75m gas; Foundry sent it with a 604k limit.
forge clean
forge script "${ARGS[@]}"
