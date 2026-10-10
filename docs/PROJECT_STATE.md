# Project state

Objective: Add owner-only atomic merging of live Shape Packs into a surviving target pack.
Phase: Sepolia v4 deployed with successful receipts; sample mint and source verification pending.
Candidate: `de77ce4` (merge) plus `81381c5` (chunked-exit test) on primary `main`.
Product rules: [DESIGN.md](../DESIGN.md), [SECURITY.md](../SECURITY.md), and [pack merge specification](PACK_MERGE_PROPOSAL.md).

The caller owns the target and every source. The target keeps its ID and gains their contents and
backing; each source token burns. Shapes stay in the same custody contract, with `packOf` updated
and no ETH or Shapes call. The operation is atomic, supports several sources, and preserves both
older `IShapePacks` ERC-165 IDs. Source insertion order is kept. The target's `mintedCount`
continues to count only Shapes minted directly by that target.

Evidence: default and testnet full Foundry suites passed for the merge implementation. The final
chunked `unseal`/`claim`/`claimEth` test passed on both profiles after it was added. `forge build`
compiled the contract; runtime bytecode is 17,715 bytes, 6,861 below the EIP-170 limit. An
independent read-only review of the immutable implementation commit `1fae168` found no concrete
custody or correctness blocker. The only review gap was merged-pack chunked-exit coverage, added
in `81381c5`; the reviewed contract code did not change afterward.

A user-provided Daybreak security diff review of `d324408...885d6d1` reported zero
findings after tracing merge custody, authorization, accounting, exits, callbacks,
events, and interface compatibility. It reports 232 passing tests on each Foundry
profile. The review did not execute a public-chain transaction, fork, deployment, or
source verification, and did not measure the gas limit for unusually large merges.

On October 10, 2026, the user ran the v4 Sepolia deployment dry run from the primary
`main` checkout. Forge reported `SIMULATION COMPLETE`. The saved artifact has two
creation transactions on chain 11155111, for the renderer and collection, and no
receipts, as expected without broadcast. The script estimated 63,306,910 gas total
across the two transactions and 0.0000648914819573 ETH at its sampled fees. Its
constructor readback assertions passed. At that stage, no v4 manifest or broadcast existed.

External state: Sepolia v4 is recorded in `deployments/11155111-v4.json` at block 11886596.
ShapePacks is `0x6db763fb3fa5b988beda8e7a4288c79d7e1e6f45` and ShapePackRenderer is
`0xbfa47d2047d61ae8eaa685008e1272e4f9d6ea60`. Both saved creation receipts have success
status and addresses matching the manifest; the deployment wrapper recorded constructor readbacks.
The v4 source has not yet been submitted or verified on Etherscan. The earlier Sepolia v3 collection
is recorded in `deployments/11155111-v3.json`; it has no merge function and cannot be upgraded.
Old pack tokens cannot directly merge into v4. Users can exit old packs and move their Shapes.

Deployment rules: The user runs all public-chain transactions from the clean primary `main`
checkout with Tenderly's public RPC and `forge clean` in deployment paths. Treat broadcast,
receipt/readback, and source verification as separate gates; never rebroadcast to fix an explorer
error. The verifier compares full creation inputs built from one deployment compilation unit and
submits only Solidity Standard JSON keys. The earlier renderer mismatch and unsupported
`allowPaths` submission were explorer verification failures after successful broadcasts.

Next: the user dry-runs and then mints six sample packs into v4 using
`script/mint_samples.sh v4` from clean primary `main`. The script reads the committed v4 manifest,
checks the collection is empty, and uses the `ripe0x` keystore for broadcast. Separately, run the
exact-input source preflight before Etherscan submission. Update event consumers and the website
merge flow before a product release.
