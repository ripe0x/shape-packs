# Project state

Phase: Sepolia release gate; awaiting rollout choice and user-operated broadcast
Branch: primary main for all deployment and verification commands
Code candidate: 6275bf4 (renderer accepted October 9, 2026); release tools e9ebd1e
Product rules: [DESIGN.md](../DESIGN.md) and [SECURITY.md](../SECURITY.md)
Launch status: Existing Sepolia contracts remain live; replacement contracts are not deployed
Blocker: the live ShapePacks producer caps the preview at eleven faces, so a renderer-only
upgrade cannot meet the accepted twelve-face rule. Three packs remain live in that collection.

The redesign draws up to twelve actual Shape faces on a transparent canvas, ordered by redeemable
backing with token-id ties. Even packs through twelve use a balanced two-card centre with smaller
faces distributed in matched left and right pairs. Odd packs retain a single highest-value face
centred in front. Three Shapes retain the Draw Shapes hero spacing. Beyond seven, even packs keep
the six-Shape face sizes and odd packs keep the seven-Shape face sizes. Every step beyond the
third tier is 180 canvas units in both layouts. The gap into the third tier
stays fixed at 170 canvas units. Packs over twelve show their top twelve cards.
The contractURI uses the same layout with three illustrative faces. Rendered
1- through 12-Shape examples are in `preview/fan-contact-sheet.png` (ignored, local review
artifact). The user accepted the layout for release. Default and testnet Foundry suites pass,
223 tests each. The release tool passed nine focused tests and independent review. From clean
primary main, `DRY_RUN=1 DEPLOYMENT_LABEL=v2 script/deploy.sh sepolia` passed against Tenderly's
public RPC with `forge clean` and constructor readback; no transactions were sent. The existing
manifest and broadcast remain unchanged. A v2 broadcast must be followed by receipt/readback
inspection and exact-input source verification before further Solidity changes.

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

Next: resolve whether Sepolia gets a new collection, an update to the old collection, or both;
then give the user the signer-owned deployment and metadata-update commands. A new collection
is required for twelve faces; the old collection can render at most eleven.
