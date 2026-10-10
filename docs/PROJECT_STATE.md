# Project state

Objective: Add owner-only atomic merging of live Shape Packs into a surviving target pack.
Phase: Sepolia v4 verified and multi-pack merge confirmed; mainnet deployed, source verification pending.
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
The owner reports both v4 contracts verified on Sepolia Etherscan. The earlier Sepolia v3
collection is recorded in `deployments/11155111-v3.json`; it has no merge function and cannot be upgraded.
Old pack tokens cannot directly merge into v4. Users can exit old packs and move their Shapes.

Six sample creation receipts succeeded, minting pack IDs 1 through 6 to `ripe0x`. Sepolia
transaction `0x771a010de68ef63d38ef971f0509941a72db51064182b0828c9703f486032823`
succeeded and emitted three `PackMerged` events: sources 5, 3 and 2 joined target 6. Live reads
show supply 3; target 6 holds 26 Shapes and 0.0069 ETH backing. Read-only Sepolia gas estimates
of `open(6)` and `redeem(6)` succeeded at 1,304,082 and 2,099,703 gas, respectively; neither
exit was broadcast. The owner confirmed both Sepolia v4 contracts are source verified.
The verifier's 11 local regression tests passed on current `main`.

The mainnet Shapes fork lifecycle test passed against Tenderly's public mainnet RPC on current
`main`. It covers creation, addition and redemption against live Shapes, not merge. The Sepolia
v4 multi-source merge above exercised the deployed merge implementation. Mainnet deployment
configuration now sets `ADMIN=0xcb43078c32423f5348cab5885911c3b5fae217f9` (`ripe0x`) as the
initial presentation admin, per the owner. Public-chain dry runs use that sender without opening
a keystore and print estimated fees. Broadcast runs perform the same keyless gas preview before
requesting the `ripe0x` keystore; the displayed fees are estimates and can change before mining.

Deployment rules: The user runs all public-chain transactions from the clean primary `main`
checkout with Tenderly's public RPC and `forge clean` in deployment paths. Treat broadcast,
receipt/readback, and source verification as separate gates; never rebroadcast to fix an explorer
error. The verifier compares full creation inputs built from one deployment compilation unit and
submits only Solidity Standard JSON keys. The earlier renderer mismatch and unsupported
`allowPaths` submission were explorer verification failures after successful broadcasts.

On October 10, 2026, the owner ran the keyless mainnet rehearsal from clean primary `main` after
`forge clean`. Solidity 0.8.28 compiled 47 files and `Deploy.s.sol` finished with its constructor
readbacks passing. The dry-run artifact records exactly two creations, no receipts, Shapes
`0x6fe9193276bf7abcbee44ab7afd717d637d6faf0`, and admin
`0xcb43078c32423f5348cab5885911c3b5fae217f9`. At the sampled 0.133016722 gwei maximum
fee, Forge estimated 8,229,944 gas and 0.001094720173123568 ETH total. The predicted renderer
and packs addresses are `0x7d5f4c54177b21332e94eafa37ad6126dca2887f` and
`0xaf1c899baacc0fe8cfba0c6cf2624a018a393def`; they matched ripe0x's pending nonce at
readback, but can change if that nonce advances.

The owner broadcast the mainnet deployment later on October 10, 2026. `deployments/1.json`
records ShapePackRenderer `0xaf1c899baacc0fe8cfba0c6cf2624a018a393def` and ShapePacks
`0xf21514b090da7df4390803497d6ae673801e5ca7`, with ripe0x as deployer and admin,
0.03 ETH minimum pack value, and preview limit 12 at block 26164530. The saved creation
transactions `0x2a718c8729dee94a2fd3d551ebb33d854d0d62ebba77a1c5fef3f5480fa53900`
and `0x5a8273e78b88a4ad3ff2a106a712ec96050401d293977fe76e33d3bdda2dd6d4`
both have successful receipts. The deployment wrapper checked live code and constructor
readbacks before writing the manifest. The read-only source preflight on primary `main`
matched both complete onchain creation inputs against one `Deploy.s.sol` build. Its Etherscan
payload is Solidity Standard JSON containing only `language`, `sources`, and `settings`.
The focused verifier tests passed (11 tests). No mainnet source submission has occurred yet.

Next: the owner submits mainnet source verification, then confirms Etherscan reports both
contracts verified. Update event consumers and the website merge flow before a public product
release.
