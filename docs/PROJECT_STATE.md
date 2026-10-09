# Project state

Phase: Renderer redesign, visual review pending
Branch: detached implementation worktree; deployment remains restricted to primary main
Code candidate: local implementation commit under visual review (current HEAD)
Product rules: [DESIGN.md](../DESIGN.md) and [SECURITY.md](../SECURITY.md)
Launch status: Existing Sepolia contracts remain live; replacement contracts are not deployed

The redesign draws up to eleven actual Shape faces, ordered by redeemable backing with token-id
ties. Packs with 2, 4, 6 or 8 Shapes use a scaled two-card centre with smaller faces distributed
in matched left and right pairs. Odd counts and counts of ten or more retain a single highest-value
face centred in front, using the Draw Shapes hero's size and tilt steps. Three Shapes retain the
hero spacing; other single-centre fans use 75% of the initial preview's centre spacing.
The contractURI uses the same layout with three illustrative faces. Rendered
1- through 12-Shape examples are in `preview/fan-contact-sheet.png` (ignored, local review
artifact). The user requested visual confirmation before the layout is final. Default and testnet
Foundry suites pass, 221 tests each; deployment and live RPC checks remain pending.

On October 9, 2026, both creation receipts succeeded. `ShapePackRenderer` is at
`0xd9ff1d1b7dd7b26a7b52c5f7f8abad7d216ceeb4` (transaction
`0x9d0eb80f63333eb903725131c8c7530669ba6b20652c2f87e8d1d39721845395`).
`ShapePacks` is at `0x5ee5186c1f66b03ba1d675ac60668e168f5306d8` (transaction
`0xfbf7851f0383fde16f0bd5ab596542cb424a8a3299da2d6f2551949d6c1479f1`).
Tenderly live reads confirm code at both addresses, the expected Shapes and renderer links,
the `ripe0x` deployer as presentation admin, and a `300000000000000` wei minimum pack value.
The verified onchain manifest is `deployments/11155111.json`.

Etherscan now shows an exact source match for both `ShapePacks` and `ShapePackRenderer`.
Forge's original one-of-two verification failure happened after both contracts deployed.
The standalone retry compiled only the renderer's 18-source import graph, while the deployment
script compiled 47 sources, so its bytecode differed. A full-input submission then failed because
Foundry's build info included the CLI-only `allowPaths` field. The corrected helper sent the full
source set with only Solidity Standard JSON keys; both public Etherscan code pages now show an
exact match. The wrapper records valid onchain state even if Forge exits nonzero after broadcast.
The release workflow now separates broadcasting from source verification. The verifier checks
both live creation transactions against one full deployment build and submits only Standard JSON
fields, so neither of the two failed retry paths is used for a future mainnet deployment.

Next: obtain visual feedback on the fan previews, then merge the accepted renderer change and
prepare a clean-main Sepolia redeployment for the user to execute.
