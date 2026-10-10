# Project state

Objective: Add owner-only atomic merging of live Shape Packs into a surviving target pack.
Phase: Contract implementation and Daybreak security review complete on primary `main`; deployment rehearsal pending.
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

External state: Sepolia v3 is recorded in `deployments/11155111-v3.json`. ShapePacks is
`0xd1cfc13abcbb370d381ac192aeb6f2e1b414022a` and ShapePackRenderer is
`0xfef50a388bde6b222c6f5fecafe590bf561c8bda`. Creation receipts and constructor readbacks
were verified, and the exact-input source preflight matched both creations. Source submission was
still pending in the last recorded project state. The v3 collection has no merge function and
cannot be upgraded. The new source has not been deployed or source-verified onchain. Existing
packs can be opened or claimed and their Shapes moved into a new collection, but a new collection
cannot directly merge old pack tokens.

Deployment rules: The user runs all public-chain transactions from the clean primary `main`
checkout with Tenderly's public RPC and `forge clean` in deployment paths. Treat broadcast,
receipt/readback, and source verification as separate gates; never rebroadcast to fix an explorer
error. The verifier compares full creation inputs built from one deployment compilation unit and
submits only Solidity Standard JSON keys. The earlier renderer mismatch and unsupported
`allowPaths` submission were explorer verification failures after successful broadcasts.

Next: the user rehearses a fresh Sepolia deployment from clean primary `main`, then
separately broadcasts, checks receipts/readbacks, and verifies source. Update event consumers and
the website merge flow before a product release. Do not present this implementation as deployed.
