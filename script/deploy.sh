#!/usr/bin/env bash
# Deploys ShapePackRenderer and ShapePacks against an existing Shapes token. The target is a
# values file (script/env/<name>.env), never a separate script.
#
# Usage:
#   script/deploy.sh <anvil|sepolia|mainnet>
#
# Environment:
#   RPC_URL               RPC endpoint. Public chains require the Tenderly URL in their env file.
#   SHAPES / ADMIN        override the env file. SHAPES is required (anvil: the local Shapes you
#                         deployed). ADMIN defaults to the broadcaster when empty.
#   PRIVATE_KEY           signer for sepolia and mainnet, or
#   KEYSTORE_ACCOUNT      a foundry keystore name (~/.foundry/keystores/<name>); forge prompts for
#                         the password, or reads KEYSTORE_PASSWORD_FILE if set.
#                         anvil needs neither: it uses anvil's well-known account 0 key.
#   SIMULATED_SENDER      public address used for the keyless gas rehearsal. Defaults to the
#                         target's configured ripe0x address and must match the broadcast signer.
#   ETHERSCAN_API_KEY     used later by script/verify_renderer.py, not by this broadcast.
#   GAS_ESTIMATE_MULTIPLIER  Sepolia env value for post-Glamsterdam creation gas.
#   FOUNDRY_PROFILE       forge profile; public chains require default so the verifier can
#                         reproduce the exact deployment build.
#   DRY_RUN=1             simulate without a keystore; no --broadcast or manifest is written.
#   DEPLOYMENT_LABEL      optional new deployment generation (for example v2); preserves the
#                         previous broadcast and records deployments/<chain>-<label>.json.
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
  if [ -n "$(git status --porcelain)" ]; then
    echo "refusing: $TARGET deploys require a clean main checkout" >&2
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

if [ "$TARGET" != "anvil" ] && [ "$RPC_URL" != "$RPC_DEFAULT" ]; then
  echo "refusing: $TARGET requires Tenderly public RPC $RPC_DEFAULT" >&2
  exit 1
fi

if [ "$TARGET" = "mainnet" ] && [ "${CONFIRM_MAINNET:-}" != "yes" ]; then
  echo "refusing: mainnet deploys require CONFIRM_MAINNET=yes" >&2
  exit 1
fi

export FOUNDRY_PROFILE="${FOUNDRY_PROFILE:-default}"
if [ "$TARGET" != "anvil" ] && [ "$FOUNDRY_PROFILE" != "default" ]; then
  echo "refusing: $TARGET requires FOUNDRY_PROFILE=default for reproducible verification" >&2
  exit 1
fi
DRY_RUN="${DRY_RUN:-0}"
SIMULATED_SENDER="${SIMULATED_SENDER:-${SIMULATED_SENDER_DEFAULT:-}}"
if [ "$TARGET" != "anvil" ] && [[ ! "$SIMULATED_SENDER" =~ ^0x[[:xdigit:]]{40}$ ]]; then
  echo "refusing: SIMULATED_SENDER must be a 20-byte address for public-chain gas rehearsal" >&2
  exit 1
fi
DEPLOYMENT_LABEL="${DEPLOYMENT_LABEL:-}"
if [ -n "$DEPLOYMENT_LABEL" ] && { [[ ! "$DEPLOYMENT_LABEL" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || [ "$DEPLOYMENT_LABEL" = latest ]; }; then
  echo "refusing: DEPLOYMENT_LABEL must contain only letters, digits, _ or -, and cannot be latest" >&2
  exit 1
fi
SUFFIX="${DEPLOYMENT_LABEL:+-$DEPLOYMENT_LABEL}"
MANIFEST="deployments/${CHAIN_ID}${SUFFIX}.json"
BROADCAST="broadcast/Deploy.s.sol/${CHAIN_ID}/run-latest.json"
ARCHIVE="broadcast/Deploy.s.sol/${CHAIN_ID}/run-before-${DEPLOYMENT_LABEL}.json"
SNAPSHOT="broadcast/Deploy.s.sol/${CHAIN_ID}/snapshot-${DEPLOYMENT_LABEL}.json"

# The chain the RPC reports must be the chain the env file names.
ACTUAL_CHAIN="$(cast chain-id --rpc-url "$RPC_URL")"
[ "$ACTUAL_CHAIN" = "$CHAIN_ID" ] \
  || { echo "refusing: $TARGET expects chain $CHAIN_ID, RPC reports $ACTUAL_CHAIN" >&2; exit 1; }

GAS_ARGS=(script/Deploy.s.sol --rpc-url "$RPC_URL")
if [ "$TARGET" = "sepolia" ] && [ -n "${GAS_ESTIMATE_MULTIPLIER:-}" ]; then
  GAS_ARGS+=(--gas-estimate-multiplier "$GAS_ESTIMATE_MULTIPLIER")
fi
ARGS=("${GAS_ARGS[@]}")

# Signer.
if [ "$TARGET" = "anvil" ]; then
  ARGS+=(--private-key "${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}")
elif [ "$DRY_RUN" = "1" ]; then
  : # The gas rehearsal uses --sender and never opens a keystore.
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

# Broadcast only. Verify source separately after receipts and live state are recorded.
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN=1: simulating only; no broadcast or deployment manifest"
else
  [ ! -e "$MANIFEST" ] \
    || { echo "refusing: $MANIFEST already exists; reconcile before redeploying" >&2; exit 1; }
  if [ -n "$DEPLOYMENT_LABEL" ] && { [ -e "$ARCHIVE" ] || [ -e "$SNAPSHOT" ]; }; then
    echo "refusing: $DEPLOYMENT_LABEL marks a prior deployment attempt; inspect receipts before retrying" >&2
    exit 1
  fi
  if [ "$TARGET" != "anvil" ] && [ -e "$BROADCAST" ]; then
    if [ -z "$DEPLOYMENT_LABEL" ]; then
      echo "refusing: prior broadcast exists; inspect receipts before retrying" >&2
      exit 1
    fi
  fi
  ARGS+=(--broadcast --slow)
fi

# Compile every attempt, including dry runs, from a clean Foundry cache.
echo "target=$TARGET chain=$CHAIN_ID profile=$FOUNDRY_PROFILE shapes=$SHAPES admin=${ADMIN:-<broadcaster>}"
forge clean
if [ "$TARGET" != "anvil" ]; then
  echo "Gas rehearsal: simulating from $SIMULATED_SENDER without a keystore"
  GAS_LOG="$(mktemp)"
  if ! forge script "${GAS_ARGS[@]}" --sender "$SIMULATED_SENDER" 2>&1 | tee "$GAS_LOG"; then
    rm -f "$GAS_LOG"
    echo "gas rehearsal failed; no keystore was opened or transaction broadcast" >&2
    exit 1
  fi
  if ! grep -q 'Estimated amount required:' "$GAS_LOG"; then
    rm -f "$GAS_LOG"
    echo "gas rehearsal did not print a fee estimate; refusing to request the keystore" >&2
    exit 1
  fi
  rm -f "$GAS_LOG"
  if [ "$DRY_RUN" = "1" ]; then
    exit 0
  fi
  echo "Gas and fee estimate shown above. Network fees may change before broadcast; keystore prompt follows."
fi
if [ "$DRY_RUN" != "1" ] && [ "$TARGET" != "anvil" ] && [ -e "$BROADCAST" ]; then
  mv "$BROADCAST" "$ARCHIVE"
  echo "preserved prior broadcast at $ARCHIVE"
fi
FORGE_STATUS=0
forge script "${ARGS[@]}" || FORGE_STATUS=$?

if [ "$DRY_RUN" = "1" ]; then
  exit "$FORGE_STATUS"
fi

if [ ! -e "$BROADCAST" ] \
  || ! python3 script/record_deployment.py "$CHAIN_ID" "$RPC_URL" "$SHAPES" "${ADMIN:-}" "$DEPLOYMENT_LABEL"; then
  echo "broadcast may have sent transactions; inspect receipts before retrying" >&2
  exit 1
fi

echo
echo "$MANIFEST:"
cat "$MANIFEST"
echo

if [ "$FORGE_STATUS" -ne 0 ]; then
  echo "both contracts deployed, but Forge exited nonzero; inspect its output before continuing" >&2
  exit "$FORGE_STATUS"
fi

if [ "$TARGET" != "anvil" ]; then
  echo "source verification pending: run python3 script/verify_renderer.py $TARGET${DEPLOYMENT_LABEL:+ --label $DEPLOYMENT_LABEL} --submit"
fi
