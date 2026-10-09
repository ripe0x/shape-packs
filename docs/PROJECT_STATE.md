# Project state

Phase: Sepolia deployed; renderer source verification pending
Branch: main (primary checkout)
Code candidate: f09773dc75f572708899ef3b6b3fcad06ec005f1
Product rules: [DESIGN.md](../DESIGN.md) and [SECURITY.md](../SECURITY.md)
Launch status: Sepolia contracts live; explorer verification incomplete

On October 9, 2026, both creation receipts succeeded. `ShapePackRenderer` is at
`0xd9ff1d1b7dd7b26a7b52c5f7f8abad7d216ceeb4` (transaction
`0x9d0eb80f63333eb903725131c8c7530669ba6b20652c2f87e8d1d39721845395`).
`ShapePacks` is at `0x5ee5186c1f66b03ba1d675ac60668e168f5306d8` (transaction
`0xfbf7851f0383fde16f0bd5ab596542cb424a8a3299da2d6f2551949d6c1479f1`).
Tenderly live reads confirm code at both addresses, the expected Shapes and renderer links,
the `ripe0x` deployer as presentation admin, and a `300000000000000` wei minimum pack value.
The verified onchain manifest is `deployments/11155111.json`.

Etherscan shows an exact source match for `ShapePacks`; `ShapePackRenderer` still needs source
verification. Forge's one-of-two verification failure happened after both contracts deployed.
The wrapper now records valid onchain state even when the explorer step exits nonzero.
The later standalone `forge verify-contract` attempt also failed: it compiled only the renderer's
18-source import graph, while the deployment script compiled 47 sources. Rebuilding
`script/Deploy.s.sol` with build info reproduces the live renderer creation bytecode exactly.
The first full-input Etherscan attempt returned `Unknown key "allowPaths"`: Foundry's build-info
input included CLI path fields. The helper now sends only Solidity Standard JSON keys.

Next: run `python3 script/verify_renderer.py sepolia` on the primary `main` checkout, then
`python3 script/verify_renderer.py sepolia --submit` with `ETHERSCAN_API_KEY` set. Confirm both
Etherscan pages show verified source. Do not broadcast the deployment script again.
