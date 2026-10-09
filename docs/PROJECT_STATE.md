# Project state

Phase: Admin preview-limit implementation reviewed; merge pending
Branch: detached implementation worktree; public-chain deployment uses primary main only
Code candidate: 081c2c5; renderer layout 6275bf4 remains accepted
Product rules: [DESIGN.md](../DESIGN.md) and [SECURITY.md](../SECURITY.md)
Launch status: Sepolia v2 deployed; user reports both contracts source-verified
Constraint: Deployed collections cannot gain the proposed setter. The original collection caps
previews at eleven; its three packs remain there. V2 starts empty and defaults to twelve.

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
223 tests each. The release tool passed ten focused tests and independent review. From clean
primary main, `DRY_RUN=1 DEPLOYMENT_LABEL=v2 script/deploy.sh sepolia` passed against Tenderly's
public RPC with `forge clean` and constructor readback; no transactions were sent. The existing
manifest and broadcast remained unchanged during rehearsal. The user then deployed v2 from
primary main. Both receipts succeeded and readbacks match. The exact-input source preflight
passed for both new creations; the user reports that Etherscan verified both.

V2 `ShapePackRenderer` is at `0x199f7d71d8d56cb721c2a71c68cc34b8f925af9c` (transaction
`0x8412c3dde9d249ccbd40777ce7d8ab424267d6eed17a277c8b64fcba01c318b5`). V2
`ShapePacks` is at `0x4974f26d743b7d39761198209776d7d3f50ba94d` (transaction
`0xdb00d33997c575c2f6a662d22db2d653b83b274c6cad02c9ad10407d72e4991b`).
The checked manifest is `deployments/11155111-v2.json`; its block is 11880142. Live reads
confirm the Shapes link, renderer link, deployer/admin and unlocked presentation. Total supply
is zero. The original collection remains unlocked with admin `0xcb43078c32423f5348cab5885911c3b5fae217f9`;
a simulated `setRenderer` to the v2 renderer succeeded.

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

Current change: `ShapePacks` starts with a 12-card preview limit and lets the presentation admin
set any positive limit until locked. It passes up to that many top-ranked Shape states; the current
renderer still draws no more than twelve. New setting affects token images only and emits an
ERC-4906 batch update. Default and testnet suites pass, 226 tests each; release-tool regressions
pass 10 tests and the deployment script builds. An independent review of 081c2c5 found no blocker;
the previous ERC-165 interface ID remains supported. The original Sepolia collection still points
to its old renderer as of the latest live read. Next: merge 1eff6b4 and 081c2c5 into primary main.
