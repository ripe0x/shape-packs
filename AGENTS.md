# Shape Packs working memory

## Deployments and source verification

- The user runs deployment and verification commands. Give commands for the primary `main`
  checkout, never a linked worktree. Public-chain RPCs use Tenderly's public URLs, and every
  deployment path includes `forge clean`.
- Treat broadcast, onchain receipt and constructor readback, and explorer source verification as
  separate gates. A failed verification does not mean a failed deployment. Inspect receipts and
  live code before suggesting any retry, and never rebroadcast to fix an explorer error.
- Before giving a verification command, check the exact payload it will send. Rebuild
  `script/Deploy.s.sol` as one compilation unit, compare each complete creation input and
  constructor arguments against the live transaction, and submit only Solidity Standard JSON
  `language`, `sources`, and `settings`. Do not pass raw Foundry build info to Etherscan or use
  standalone contract compilation to infer the deployment bytecode.
- Run `python3 script/test_verify_renderer.py` and the read-only
  `python3 script/verify_renderer.py <sepolia|mainnet>` preflight before recommending
  `--submit`. State plainly when an external submission has not yet been tested.
