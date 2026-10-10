# Shape Packs

Bundle Shapes into one token. Its value is exactly theirs.

A Shape Pack is an ERC-721 in the `ShapePacks` collection that custodies a set of live, non-Black
[Shapes](https://github.com/ripe0x/shapes). The pack contract holds the Shapes; the pack token is
the claim on them. A pack is built from Shapes you already hold, from ETH minted into Shapes on the
spot, or both, at whatever makeup you choose. It has five properties.

- **Sealed against removal.** Nothing leaves a live pack. The holder may add Shapes or merge in
  other packs they own, so contents only grow while the pack is live. A buyer gets at least the
  Shapes the metadata listed when they looked, and exactly the Shapes it lists when they receive it.
- **Exact value.** A pack's value is the sum of its Shapes' redeemable backing. It is cached at
  creation, increased on every addition or merge, and asserted equal to the live sum by the invariant suite.
  It never decreases: no one can redeem, split, compose or blacken a packed Shape.
- **Minimum `3 * shapes.unit()` at creation:** 0.03 ETH on mainnet and 0.0003 ETH on Sepolia's
  1/100 ladder. Neither minimum is a denomination; the smallest packs are three unit Shapes or
  one Shape at the next denomination (0.05 ETH on mainnet, 0.0005 ETH on Sepolia). Additions have
  no minimum.
- **No cap on size.** A pack may hold as many Shapes as its creator will pay gas for, across as many
  transactions as they like. Exit is chunkable, so no pack can outgrow its own exit.
- **Two exits, all-or-nothing at the token level.** `open` burns the pack and hands the Shapes
  back. `redeem` burns the pack and unwraps every Shape to ETH. `unseal` burns the pack and turns
  what is inside into a claim drained in chunks. There is no partial exit from a live pack.

`ShapePacks` also implements the draft ERC-8060 `IERC721Value` surface Shapes does: `valueOf(packId)`
and `burn(packId)`. A pack is transparent, not a blind box: contents are readable onchain from the
moment it exists. The wrapper charges no fee of its own.

The specification is [DESIGN.md](DESIGN.md). The trust model and the accepted residuals are in [SECURITY.md](SECURITY.md).

---

## Creating a pack

```solidity
function createPack(uint256[] calldata shapeIds, uint32[] calldata mintCounts)
    external payable returns (uint256 packId);

function createPackTo(uint256[] calldata shapeIds, uint32[] calldata mintCounts, address to)
    external payable returns (uint256 packId);
```

There are two inputs, and either may be empty as long as the pack ends up with at least one Shape.

- `shapeIds`: Shapes you own. Each is pulled with `transferFrom(msg.sender, this, id)`. A Shape with
  zero backing (a Black Shape) is refused with `WorthlessShape(id)`: a pack values by backing, never
  by denomination.
- `mintCounts`: the makeup of the minted portion, one entry per ladder index, so its length must be
  `shapes.denominationCount()`. Entry `d` is how many Shapes of denomination `d` to mint fresh into
  the pack.

The ETH you send is not a free input. It is determined by `mintCounts` and must match exactly:

```
msg.value == sum over d of mintCounts[d] * (shapes.denominationAt(d) + shapes.mintFee())
```

Over and under both revert `IncorrectPayment(expected, provided)`. With no mints, `msg.value` must
be zero. Each minted Shape pays Shapes' flat per-Shape mint fee, which accrues to Shapes' fee
recipient as it would for any mint; `ShapePacks` adds nothing to it. Because payment is exact, a fee
change between quote and inclusion reverts the creation rather than overcharging you.

Two views help a UI that starts from an ETH amount:

```solidity
function quoteMint(uint32[] calldata mintCounts) external view
    returns (uint256 backingWei, uint256 feeWei, uint256 totalWei, uint256 shapeCount);

/// Fewest-Shapes makeup for a backing amount (largest denomination first), as a prefill.
function defaultMakeup(uint256 backingWei) external view returns (uint32[] memory mintCounts);
```

`quoteMint(...).totalWei` is the `msg.value` to send. `defaultMakeup` reverts `NotAUnitMultiple`
for an amount that is not a whole number of `unit()`s, and is only a prefill: `createPack` takes
whatever makeup you give it.

Creation checks, in this order: `MakeupLengthMismatch`, `NoShapes`, `IncorrectPayment`,
`WorthlessShape` and the pulls, the mints, then `PackBelowMinimum(valueWei, MIN_PACK_VALUE)`. The
pack token is minted last, to `to` (the caller for `createPack`). A contract recipient must
implement `IERC721Receiver`. Minting from ETH needs Shapes' `mintStart` to have passed; mainnet
opened on 2026-09-03.

### Approvals

Pulling Shapes needs approval, ideally one `setApprovalForAll(shapePacks, true)` on Shapes rather
than one approval per Shape. This is safe to grant because every pull is
`transferFrom(msg.sender, this, id)`: the contract only ever pulls from the account that called it.
An approval to `ShapePacks` therefore lets the approver's own calls pull the approver's own Shapes
into a pack the approver creates or owns. It is not a grant to anyone else, and no third party can
use it to move your Shapes.

## Adding to a pack

```solidity
function addToPack(uint256 packId, uint256[] calldata shapeIds, uint32[] calldata mintCounts)
    external payable;
```

The owner of a live pack can add Shapes, pulled, minted, or both, under the same rules as creation
(length, at least one Shape, exact payment, pulls, mints) but with no minimum value. The cached
value and minted count increase, and the call emits `PackExtended` and the ERC-4906
`MetadataUpdate`. Only the owner can add. An approved operator cannot, for the same reason an
operator cannot open: every value-affecting action on a pack is owner-only. Additions are also how a
very large pack is built, one block-sized transaction at a time.

## Merging packs

```solidity
function mergePacks(uint256 targetPackId, uint256[] calldata sourcePackIds) external;
```

The owner of every named pack can merge one or more live sources into a live target. Sources are
processed in the order given, with each source's Shape order preserved. The target retains its ID,
owner and creator; its contents and exact backing value grow. Each source token is burned. Shapes
stay in the same contract, so the merge needs no Shape approval, ETH or mint fee. An approved pack
operator cannot merge without taking ownership first. The call is atomic and rejects an empty
source list, self-merge, repeated source, or any pack the caller does not own.

`PackMerged` identifies each burned source, its Shape IDs and value, and the target's new value;
one `MetadataUpdate` is emitted for the target. The target's `mintedCount` does not include Shapes
minted by source packs. There is no size cap, but a very large merge may exceed block gas. Its
owner can instead unseal a source, claim Shapes in chunks and add them to the target in chunks.
The deployed collections cannot gain this function; it requires a new `ShapePacks` deployment.

## Exiting a pack

Every exit is owner-only. An approved operator can transfer a pack but cannot open, redeem or
unseal it.

```solidity
function open(uint256 packId) external;                                 // Shapes to msg.sender
function openTo(uint256 packId, address to) external;                   // Shapes to `to`
function redeem(uint256 packId) external;                               // ETH to msg.sender
function redeemTo(uint256 packId, address payable recipient) external;  // ETH to `recipient`
function burn(uint256 packId) external;                                 // IERC721Value, same as redeem
```

`open` burns the pack token, clears its state, then transfers every Shape out with plain
`transferFrom`. `redeem` burns the pack token, clears its state, then makes one call to
`shapes.redeemBatchTo`: Shapes burns every Shape and pays the recipient once; the pack contract never
touches the ETH. If the recipient rejects ETH the whole transaction reverts and the pack is untouched.
No pack can hold zero value, so `burn` always pays and is identical to `redeem`.

### Large packs

There is no size cap, so exit cost scales with pack size: a large enough pack cannot be opened or
redeemed in one block. For those, exit in chunks.

```solidity
function unseal(uint256 packId, address claimant) external;                              // owner only
function claim(uint256 packId, uint256 maxCount) external;                               // claimant only
function claimEth(uint256 packId, uint256 maxCount, address payable recipient) external; // claimant only
function claimantOf(uint256 packId) external view returns (address);                     // zero when none
```

`unseal` burns the pack token and records `claimant` as the only account that may drain what is
left. The pack is no longer an NFT and cannot be sold half-drained; what remains is a claim.
`claim` transfers up to `maxCount` Shapes from the end of the remaining list to the claimant.
`claimEth` redeems up to `maxCount` to `recipient` in one `redeemBatchTo`. They may be mixed freely
across transactions. When the list is empty the claimant entry is cleared. `maxCount == 0` reverts
`ZeroQuantity()`.

`open` is `unseal(msg.sender)` followed by `claim(all)`, and `redeem` is `unseal(msg.sender)` followed
by `claimEth(all, recipient)`, so every exit emits the same events: `PackUnsealed`, then
`ShapesClaimed` or `EthClaimed`. Choose `maxCount` to fit the block: each Shape is one transfer
for `claim` and one redemption inside Shapes' `redeemBatchTo` for `claimEth`.

## Reading a pack

```solidity
function contentsOf(uint256 packId) external view returns (uint256[] memory shapeIds); // live: contents; unsealed: what remains
function valueOf(uint256 packId) external view returns (uint256);        // cached sum of backingOf; reverts unless live
function packOf(uint256 shapeId) external view returns (uint256);        // 0 when not packed
function makeupOf(uint256 packId) external view returns (uint32[] memory counts); // per ladder index, live pack only
function packState(uint256 packId) external view returns (PackState memory);      // live pack only
function exists(uint256 packId) external view returns (bool);            // live pack token; never reverts
function creatorOf(uint256 packId) external view returns (address);      // survives unsealing
function claimantOf(uint256 packId) external view returns (address);

function MIN_PACK_VALUE() external view returns (uint256);               // immutable, 3 * shapes.unit()
function shapes() external view returns (address);
function totalMinted() external view returns (uint256);                  // packs ever created
function totalSupply() external view returns (uint256);                  // live packs

struct PackState {
    uint256[] shapeIds;
    uint32[]  counts;        // per ladder index
    uint256   valueWei;
    uint256   mintedCount;   // Shapes the pack minted itself, at creation and in additions
    address   creator;
}
```

Pack ids start at 1 and are never reissued, so `packOf(shapeId) == 0` means "not packed". That is
the hook a site or indexer uses to say "this Shape is inside Pack #N". `tokenURI(packId)` is a
fully onchain `data:` URI: the current renderer draws up to twelve real Shape faces on a transparent
canvas, with highest redeemable backing in front and equal-value ties broken by token id. Even
fans show a balanced centre pair, with smaller faces distributed on both sides. `ShapePacks`
passes up to its admin-set `previewCardLimit()` highest-backed Shapes to the renderer (default 12);
a future renderer can use more than twelve. The current renderer still draws at most twelve.
The full makeup remains in the description and attributes. Display order does not change
contents or custody.

## Trust model

The contract holds other people's claims on ETH, so it inherits Shapes' posture. The full account
is in [SECURITY.md](SECURITY.md); in short, the contract never:

- calls `compose`, `decompose`, `split`, `burnBacking`, `approve` or `setApprovalForAll` on Shapes.
  The only Shapes mutators it calls are `mintBatchTo` and `redeemBatchTo`;
- retains ETH from normal calls. Creation and additions forward `msg.value` exactly into Shapes
  mints; redemption is paid by Shapes straight to the recipient. `receive` and `fallback` revert;
  forced ETH can still be stranded;
- accepts an unsolicited safe Shape transfer. `onERC721Received` admits only a Shapes mint the
  contract itself is performing; a `safeTransferFrom` into it reverts `UnsolicitedToken`;
- exposes any administrative path into custody. There is no pause, recovery, upgrade or allowlist.

An `admin()` exists, and reaches presentation only: it can replace the renderer, set a positive
preview-card limit, edit the name prefix and description (bounded, JSON-safe), and permanently
`lockPresentation()`. It cannot touch a Shape, a pack, ETH, or who may exit. A large preview limit
can make metadata reads expensive. Hold the admin in a multisig until the art is final, then lock it.

Two things worth knowing before you use it. A Shape sent into the contract by plain `transferFrom`
(not through `createPack`) is stranded; see SECURITY.md. And exit cost scales with pack size;
`unseal` and `claim` guarantee any pack can be exited, but they are the way out for a large one.

## Repository layout

```
src/
  ShapePacks.sol             ERC-721 + custody + create/add/exit + views + presentation admin
  ShapePackRenderer.sol      the stack image, metadata JSON, contractURI
  interfaces/
    IShapePacks.sol          every function, event and error, with NatSpec
    IShapePackRenderer.sol   PackRenderInput, tokenURI, metadataJSON, image, contractURI
lib/
  shapes/                    git submodule at the deployed mainnet commit; carries OpenZeppelin and forge-std
script/
  Deploy.s.sol               one script, chain-id gated: anvil, sepolia, mainnet
  deploy.sh                  the wrapper; reads script/env/<target>.env
  record_deployment.py       checks receipts and live state before writing the manifest
  env/{anvil,sepolia,mainnet}.env   SHAPES per chain, ADMIN; nothing secret
deployments/                 <chainId>.json, written after a verified broadcast
test/                        creation, additions, exits, receiver, metadata, invariants, fork
foundry.toml                 profiles, remappings, rpc endpoints
```

There is one copy of each dependency: the OpenZeppelin and forge-std vendored inside the Shapes
submodule, so the pack is built against exactly what Shapes was. `ShapePacks` is ladder-agnostic:
it reads `unit()`, `denominationCount()`, `denominationAt(d)` and `mintFee()` from Shapes live, so
one build deploys to mainnet and Sepolia.

## Building and testing

Foundry, `solc 0.8.28`, `evm_version = cancun`, `via_ir`.

```sh
git clone --recursive https://github.com/ripe0x/shape-packs
cd shape-packs

forge build
forge test                                # mainnet ladder
FOUNDRY_PROFILE=testnet forge test        # the 1/100 ladder public testnets use
FOUNDRY_PROFILE=ci forge test             # 1024 fuzz runs, deeper invariant runs
```

If you cloned without `--recursive`, run `git submodule update --init --recursive`. The profiles
differ only in the denomination table of the Shapes build the local tests deploy and in the
fuzz and invariant depth; the pack contract is the same bytecode. The fork test is gated on
`MAINNET_RPC_URL` and runs the lifecycle against the deployed mainnet Shapes:

```sh
MAINNET_RPC_URL=https://ethereum-rpc.publicnode.com forge test --mc ForkTest
```

To look at the artwork without deploying anything, `forge script script/Preview.s.sol` writes the
`tokenURI` of 1- through 12-Shape packs and the `contractURI` to `preview/` from a
throwaway local Shapes. Decode the base64 JSON and its `image` field to get the SVGs.

## Deploying

```sh
forge clean
script/deploy.sh <anvil|sepolia|mainnet>
```

`script/deploy.sh` sources `script/env/<target>.env` (values only, no secrets), checks the RPC chain,
runs `forge clean`, then runs `forge script script/Deploy.s.sol --broadcast --slow`. Source
verification is a separate step after receipts and live constructor state have been recorded.
Run public-chain targets from the clean primary checkout on `main`; the wrapper refuses linked
worktrees, dirty checkouts and other branches.
The wrapper pins Tenderly's public RPC and Foundry's `default` profile on public chains so the
later source-verification build uses the same inputs.
Public-chain dry runs use the configured `ripe0x` public address and need no keystore password.
Before every public-chain broadcast, the wrapper first simulates without a key, prints Foundry's
gas and fee estimate, and stops if no estimate appears. Only then does it request the keystore.
The estimate is a snapshot; network fees can change before the signed transactions land.
The wrapper refuses to overwrite an existing deployment manifest. For a deliberate new generation,
set `DEPLOYMENT_LABEL` (for example `v3`); it archives the prior broadcast and records an immutable
snapshot for later verification. An interrupted attempt must be reconciled before another broadcast.

After a public-chain deployment, verify both contracts without broadcasting:

```sh
python3 script/verify_renderer.py sepolia          # read-only preflight for both contracts
python3 script/verify_renderer.py sepolia --submit # requires ETHERSCAN_API_KEY
```

For a labelled deployment, add `--label <label>` to both verification commands.

The helper runs `forge clean`, builds `script/Deploy.s.sol` with build info, and checks each
contract's complete creation bytecode against its live Tenderly transaction before submitting
the same Standard JSON source and settings to Etherscan. It permits only Solidity's three
Standard JSON input keys; Foundry-only path fields caused an earlier verification failure.
Compiling `ShapePackRenderer.sol` alone also produces different bytecode because its `via_ir`
build has a smaller compiler source set. Use `mainnet` instead of `sepolia` when verifying a
mainnet deployment. A successful broadcast is not a completed source-verification gate.

Sepolia has Glamsterdam's higher code-deposit cost. The env file sets a 1000% gas-estimate
multiplier because this Foundry build simulates Cancun costs. The transactions are sent
sequentially so a failed renderer creation cannot be followed by a packs creation.

To mint six sample packs of 1, 2, 3, 6, 9 and 12 Shapes into an empty, labelled Sepolia
collection, run from the clean primary `main` checkout. The wrapper reads the collection address
from `deployments/11155111-<label>.json` and uses the `ripe0x` keystore:

```sh
DRY_RUN=1 script/mint_samples.sh v4 # read-only rehearsal
script/mint_samples.sh v4           # prompts for the ripe0x keystore password
```

The wrapper includes `forge clean`, Tenderly's public Sepolia RPC, sequential receipts and a
1000% gas-estimate multiplier. This matters for mint execution too: a prior first mint reverted
with a 604,025 gas limit; Tenderly estimated 1,753,633 gas for the same call. It refuses to
rebroadcast after any pack is minted or a prior sample broadcast was saved. If a broadcast fails,
inspect its receipts and live pack count before retrying.

| Variable | Meaning |
| --- | --- |
| `RPC_URL` | RPC endpoint. Sepolia and mainnet default to Tenderly's public RPC URLs. |
| `SHAPES` | The Shapes token to wrap. Set in the env file; the shell wins. Required. |
| `ADMIN` | Presentation admin. Defaults to the broadcaster when empty. |
| `PRIVATE_KEY` | Signer for `sepolia` and `mainnet`... |
| `KEYSTORE_ACCOUNT` | ...or the name of a foundry keystore under `~/.foundry/keystores` (password prompt, or `KEYSTORE_PASSWORD_FILE`). |
| `SIMULATED_SENDER` | Public signer address for the keyless gas rehearsal; defaults to `ripe0x` and must match the broadcast signer. |
| `ETHERSCAN_API_KEY` | Separate source-verification step on `sepolia` and `mainnet`. |
| `DEPLOYMENT_LABEL` | New deployment generation, such as `v3`; preserves the previous record and broadcast. |
| `DRY_RUN=1` | Simulate without a keystore: no broadcast or deployment manifest; Foundry may save a dry-run artifact. |
| `CONFIRM_MAINNET=yes` | Required to run `mainnet` at all, dry run included. |

`anvil` needs no key: it uses anvil's well-known account 0. Its env file leaves `SHAPES` empty,
because the local flow deploys Shapes first: start `anvil`, deploy Shapes to it with the script in
the [Shapes repository](https://github.com/ripe0x/shapes) (`script/deploy.sh anvil`), then

```sh
SHAPES=<local Shapes address> script/deploy.sh anvil
```

`Deploy.s.sol` is gated by chain id. On chain 1, `SHAPES` must be
`0x6fe9193276bf7abcbee44ab7afd717d637d6faf0`. On Sepolia any nonzero address is accepted, and the
env file names the live Sepolia Shapes. On 31337, any nonzero address. Any other chain reverts. It
deploys `ShapePackRenderer(shapes)`, then `ShapePacks(shapes, renderer, admin)`, then reads back
and requires:

- `packs.shapes() == SHAPES`, `packs.renderer() == renderer`, `packs.admin() == admin`
- `packs.previewCardLimit() == 12`
- `packs.MIN_PACK_VALUE() == 3 * IShapes(SHAPES).unit()`
- `renderer.shapes() == SHAPES`
- `packs.supportsInterface(type(IShapePacks).interfaceId)`

After a broadcast, the wrapper checks both receipts and live constructor state through the RPC.
Only then does it write `deployments/<chainId>[-<label>].json` with `chainId`, `shapes`,
`shapePacks`, `shapePackRenderer`, `admin`, `minPackValueWei` (a decimal string),
`previewCardLimit`, `deployer` and `blockNumber` (the latest deployment block).
If Forge exits nonzero after both contracts deploy,
the wrapper still records their verified onchain state, then exits nonzero for investigation.
Inspect receipts before any retry. Presentation is left
unlocked at launch, as Shapes' was; lock it once the art is final.

## License

MIT. See [LICENSE](LICENSE).
