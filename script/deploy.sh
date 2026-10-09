#!/usr/bin/env bash
# Deploys ShapePackRenderer and ShapePacks against an existing Shapes token. The target is a
# values file (script/env/<name>.env), never a separate script.
#
# Usage:
#   script/deploy.sh <anvil|sepolia|mainnet>
#
# Environment:
#   RPC_URL               RPC endpoint. Defaults to the env file's RPC_DEFAULT.
#   SHAPES / ADMIN        override the env file. SHAPES is required (anvil: the local Shapes you
#                         deployed). ADMIN defaults to the broadcaster when empty.
#   PRIVATE_KEY           signer for sepolia and mainnet, or
#   KEYSTORE_ACCOUNT      a foundry keystore name (~/.foundry/keystores/<name>); forge prompts for
#                         the password, or reads KEYSTORE_PASSWORD_FILE if set.
#                         anvil needs neither: it uses anvil's well-known account 0 key.
#   ETHERSCAN_API_KEY     required for sepolia and mainnet (--verify).
#   GAS_ESTIMATE_MULTIPLIER  Sepolia env value for post-Glamsterdam creation gas.
#   FOUNDRY_PROFILE       forge profile; defaults to default. The contracts are ladder-agnostic,
#                         so the same build deploys to every target.
#   DRY_RUN=1             simulate only: no --broadcast, nothing written.
#   CONFIRM_MAINNET=yes   required to run the mainnet target at all, dry run included.
set -euo pipefail

TARGET="${1:-}"
case "$TARGET" in
  anvil | sepolia | mainnet) ;;
  *)
    echo "usage: script/deploy.sh <anvil|sepolia|mainnet>" >&2
    exit 1
    ;;
esac

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Public-chain deployments must use the primary checkout on main, never a linked worktree.
if [ "$TARGET" != "anvil" ]; then
  if [ "$(git branch --show-current)" != "main" ] \
    || [ "$(git rev-parse --path-format=absolute --git-dir)" != "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
    echo "refusing: $TARGET deploys require the primary main checkout" >&2
    exit 1
  fi
fi

# A caller's exports win over the env file.
CALLER_SHAPES="${SHAPES-}"
CALLER_ADMIN="${ADMIN-}"
set -a
# shellcheck disable=SC1090
source "script/env/${TARGET}.env"
set +a
[ -n "$CALLER_SHAPES" ] && SHAPES="$CALLER_SHAPES"
[ -n "$CALLER_ADMIN" ] && ADMIN="$CALLER_ADMIN"

RPC_URL="${RPC_URL:-${RPC_DEFAULT:-}}"
: "${RPC_URL:?RPC_URL is required}"
: "${SHAPES:?SHAPES is required: set it in script/env/${TARGET}.env or the environment}"
[ -n "${ADMIN:-}" ] || unset ADMIN
export SHAPES

if [ "$TARGET" = "mainnet" ] && [ "${CONFIRM_MAINNET:-}" != "yes" ]; then
  echo "refusing: mainnet deploys require CONFIRM_MAINNET=yes" >&2
  exit 1
fi

export FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-default}"
DRY_RUN="${DRY_RUN:-0}"

# The chain the RPC reports must be the chain the env file names.
ACTUAL_CHAIN="$(cast chain-id --rpc-url "$RPC_URL")"
[ "$ACTUAL_CHAIN" = "$CHAIN_ID" ] \
  || { echo "refusing: $TARGET expects chain $CHAIN_ID, RPC reports $ACTUAL_CHAIN" >&2; exit 1; }

ARGS=(script/Deploy.s.sol --rpc-url "$RPC_URL")
if [ "$TARGET" = "sepolia" ] && [ -n "${GAS_ESTIMATE_MULTIPLIER:-}" ]; then
  ARGS+=(--gas-estimate-multiplier "$GAS_ESTIMATE_MULTIPLIER")
fi

# Signer.
if [ "$TARGET" = "anvil" ]; then
  ARGS+=(--private-key "${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}")
elif [ -n "${PRIVATE_KEY:-}" ]; then
  ARGS+=(--private-key "$PRIVATE_KEY")
elif [ -n "${KEYSTORE_ACCOUNT:-}" ]; then
  if [ -n "${KEYSTORE_PASSWORD_FILE:-}" ]; then
    ARGS+=(--keystore "$HOME/.foundry/keystores/$KEYSTORE_ACCOUNT" --password-file "$KEYSTORE_PASSWORD_FILE")
  else
    ARGS+=(--account "$KEYSTORE_ACCOUNT")
  fi
else
  echo "refusing: set PRIVATE_KEY or KEYSTORE_ACCOUNT for $TARGET" >&2
  exit 1
fi

# Broadcast and verification.
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN=1: simulating only, nothing is broadcast or written"
else
  [ ! -e "deployments/${CHAIN_ID}.json" ] \
    || { echo "refusing: deployments/${CHAIN_ID}.json already exists; reconcile before redeploying" >&2; exit 1; }
  if [ "$TARGET" != "anvil" ] && [ -e "broadcast/Deploy.s.sol/${CHAIN_ID}/run-latest.json" ]; then
    echo "refusing: prior broadcast exists; inspect receipts and archive run-latest.json before retrying" >&2
    exit 1
  fi
  ARGS+=(--broadcast --slow)
  if [ "$TARGET" != "anvil" ]; then
    : "${ETHERSCAN_API_KEY:?ETHERSCAN_API_KEY is required to verify on $TARGET}"
    ARGS+=(--verify)
  fi
fi

# Compile every attempt, including dry runs, from a clean Foundry cache.
forge clean
echo "target=$TARGET chain=$CHAIN_ID profile=$FOUNDRY_PROFILE shapes=$SHAPES admin=${ADMIN:-<broadcaster>}"
if ! forge script "${ARGS[@]}"; then
  if [ "$DRY_RUN" != "1" ]; then
    echo "broadcast may have sent transactions; inspect receipts before retrying" >&2
  fi
  exit 1
fi

if [ "$DRY_RUN" != "1" ]; then
  if ! python3 script/record_deployment.py "$CHAIN_ID" "$RPC_URL" "$SHAPES" "${ADMIN:-}"; then
    echo "broadcast may have succeeded; reconcile receipts before retrying" >&2
    exit 1
  fi
  echo
  echo "deployments/${CHAIN_ID}.json:"
  cat "deployments/${CHAIN_ID}.json"
  echo
fi
