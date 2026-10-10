# Pack merge specification

Status: implemented in source, not deployed. This describes a future `ShapePacks` deployment.
Existing deployed collections are not upgradeable and cannot gain this
entrypoint. It merges packs in one collection; it does not nest pack tokens or change `Shapes`.

## Behavior

```solidity
function mergePacks(uint256 targetPackId, uint256[] calldata sourcePackIds) external;

event PackMerged(
    uint256 indexed targetPackId,
    uint256 indexed sourcePackId,
    address indexed by,
    uint256[] shapeIds,
    uint256 addedValueWei,
    uint256 valueWei
);

error NoSourcePacks();
error CannotMergePackIntoItself(uint256 packId);
```

The caller must own the live target and every live source. An ERC-721 approval or operator approval
does not suffice, matching `addToPack` and every exit. At least one source is required. A source
cannot be the target. Repeated source IDs fail when the second occurrence is checked; the whole
transaction reverts, including earlier merges. A missing, burned, or unsealed pack fails the
existing `NotPackOwner(packId, caller)` check. The function is nonpayable and `nonReentrant`.

Sources are processed in calldata order. For each source, append its Shapes in their existing
insertion order to the target, set every `packOf(shapeId)` to `targetPackId`, add the source's cached
value to the target's cached value, clear the source's contents and cached value, burn its pack
token, and decrement live supply by one. The destination's original contents remain a prefix.
`totalMinted` does not change. No Shape is transferred or redeemed: the same `ShapePacks` contract
already owns them, so no Shape approval, ETH payment, or Shapes call is needed.

The target keeps its owner, pack ID and `creatorOf`. Its `mintedCount` does **not** rise: that field
counts Shapes minted by this particular pack at creation or addition, not Shapes minted by a
different pack before merging. The source's `creatorOf` and historical minted count remain stored;
only `creatorOf` is externally readable after its token is burned. After a merge,
`exists(source)` is false; `contentsOf(source)` is empty;
`packOf` names the target for every moved Shape; `valueOf`, `makeupOf`, `packState` and `tokenURI`
revert for the source. The source becomes neither an unsealed claim nor redeemable ETH.

For each source, emit its ERC-721 burn `Transfer`, then `PackMerged` with exactly the Shape IDs
moved, their cached backing, and the target's new cumulative value. After all sources, emit one
ERC-4906 `MetadataUpdate(targetPackId)`. Do not emit `PackUnsealed`, `ShapesClaimed`, or
`PackExtended`: none describes this operation accurately. Indexers can replay the per-source
events and distinguish a merge from an exit. Update ERC-165 support to retain both existing
`IShapePacks` interface IDs when adding the new selector to the interface.

The whole call is atomic. Any failed ownership or validity check, arithmetic failure, or gas
exhaustion leaves every pack and Shape unchanged. No external callback occurs during the merge.
Presentation admin rights remain presentation-only; the admin cannot merge users' packs.

## Size and recovery

There is no new size cap. The call touches every source Shape and may exceed a block's gas limit
for very large sources. This does not trap the Shapes: the owner can `unseal` a source, `claim`
its Shapes in chunks, approve the collection, then `addToPack` in chunks. That fallback burns the
source pack and requires more transactions; it cannot keep the source NFT live during draining.

## Acceptance cases

1. Merge one source into a target and then merge two more in one call. The target's old IDs stay
   first; each source's IDs follow in argument and insertion order. Its value equals the sum of
   all previous values. Only the target remains live, and `totalMinted` is unchanged.
2. A source containing a Shape minted by its own pack increases the target's value and contents,
   but leaves the target's `mintedCount` unchanged. Existing source provenance remains readable
   through `creatorOf` and historical events.
3. A call from a token-approved operator, a call with a source owned by someone else, a self-merge,
   an empty list, a repeated source, and a burned or unsealed source each revert without partial
   changes. A reverted transaction leaves all pack ownership and Shape mappings unchanged.
4. Merge emits the burn and merge event for each source and one target metadata update. There are
   no Shapes transfers, ETH movements, claimants, or calls to Shapes.
5. Creation, addition, open, redeem, unseal and chunked claim still satisfy the existing custody,
   cached-value, grow-only, supply and exit invariants after any successful merge.

## Release scope

The interface, contract and tests implement this behavior. Event consumers/indexer and UI
transaction flow must recognize the new operation before a product release. Rehearse against a
fresh Sepolia deployment, including real receipts and
source verification, before recommending a mainnet deployment. Existing Sepolia and mainnet packs
cannot be merged directly by a new contract; their holders can open or claim them and create or
extend a pack in the new collection.
