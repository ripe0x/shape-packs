// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PacksTest} from "./utils/PacksTest.sol";
import {IShapePacks, PackState} from "../src/interfaces/IShapePacks.sol";

/// @notice Merging moves Shapes between live packs without moving the Shapes out of custody.
contract MergeTest is PacksTest {
    function _mintPack(address who, uint256 denomination, uint32 count) private returns (uint256 packId) {
        uint32[] memory counts = mintsOf(denomination, count);
        uint256 cost = costOf(counts);
        vm.prank(who);
        packId = packs.createPack{value: cost}(new uint256[](0), counts);
    }

    function _assertSourceBurned(uint256 packId) private {
        assertFalse(packs.exists(packId));
        assertEq(packs.contentsOf(packId).length, 0);
        assertEq(packs.claimantOf(packId), address(0));
        vm.expectRevert();
        packs.valueOf(packId);
        vm.expectRevert();
        packs.packState(packId);
        vm.expectRevert();
        packs.tokenURI(packId);
    }

    function test_MergeMultipleSourcesInOrderAndPreserveProvenance() public {
        uint256 target = _mintPack(alice, 1, 1);
        uint256 first = _mintPack(alice, 0, 3);
        uint256 second = _mintPack(bob, 1, 1);
        uint256 third = _mintPack(alice, 2, 1);
        vm.prank(bob);
        packs.transferFrom(bob, alice, second);

        uint256[] memory targetIds = packs.contentsOf(target);
        uint256[] memory firstIds = packs.contentsOf(first);
        uint256[] memory secondIds = packs.contentsOf(second);
        uint256[] memory thirdIds = packs.contentsOf(third);
        uint256 targetValue = packs.valueOf(target);
        uint256 firstValue = packs.valueOf(first);
        uint256 secondValue = packs.valueOf(second);
        uint256 thirdValue = packs.valueOf(third);
        uint256 totalMinted = packs.totalMinted();

        vm.recordLogs();
        vm.prank(alice);
        packs.mergePacks(target, ids1(first));
        vm.prank(alice);
        packs.mergePacks(target, ids2(second, third));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256[] memory expected =
            new uint256[](targetIds.length + firstIds.length + secondIds.length + thirdIds.length);
        uint256 at;
        for (uint256 i = 0; i < targetIds.length; ++i) {
            expected[at++] = targetIds[i];
        }
        for (uint256 i = 0; i < firstIds.length; ++i) {
            expected[at++] = firstIds[i];
        }
        for (uint256 i = 0; i < secondIds.length; ++i) {
            expected[at++] = secondIds[i];
        }
        for (uint256 i = 0; i < thirdIds.length; ++i) {
            expected[at++] = thirdIds[i];
        }

        assertEq(packs.totalMinted(), totalMinted);
        assertEq(packs.totalSupply(), 1);
        assertEq(packs.creatorOf(first), alice);
        assertEq(packs.creatorOf(second), bob);
        assertEq(packs.creatorOf(third), alice);
        _assertSourceBurned(first);
        _assertSourceBurned(second);
        _assertSourceBurned(third);
        assertEq(packs.ownerOf(target), alice);
        assertEq(packs.creatorOf(target), alice);
        assertEq(packs.valueOf(target), targetValue + firstValue + secondValue + thirdValue);
        PackState memory state = packs.packState(target);
        assertEq(state.mintedCount, 1, "only the target's own mint counts");
        assertEq(state.shapeIds, expected, "source and insertion order");
        for (uint256 i = 0; i < expected.length; ++i) {
            assertEq(packs.packOf(expected[i]), target);
            assertEq(shapes.ownerOf(expected[i]), address(packs));
        }

        uint256 burnCount;
        uint256 mergeCount;
        uint256 metadataCount;
        uint256 shapeTransferCount;
        uint256 packLogStage;
        uint256[] memory mergedSources = new uint256[](3);
        for (uint256 i = 0; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.emitter == address(shapes) && log.topics[0] == IERC721.Transfer.selector) {
                ++shapeTransferCount;
            }
            if (log.emitter != address(packs)) continue;
            if (log.topics[0] == IERC721.Transfer.selector) {
                assertTrue(packLogStage == 0 || packLogStage == 3 || packLogStage == 5, "burn order");
                assertEq(log.topics[2], bytes32(0), "burn destination");
                ++burnCount;
            } else if (log.topics[0] == IShapePacks.PackMerged.selector) {
                assertTrue(packLogStage == 1 || packLogStage == 4 || packLogStage == 6, "merge order");
                assertEq(uint256(log.topics[1]), target);
                assertEq(address(uint160(uint256(log.topics[3]))), alice);
                (uint256[] memory ids, uint256 added, uint256 newValue) =
                    abi.decode(log.data, (uint256[], uint256, uint256));
                if (mergeCount == 0) {
                    assertEq(ids, firstIds);
                    assertEq(added, firstValue);
                    assertEq(newValue, targetValue + firstValue);
                } else if (mergeCount == 1) {
                    assertEq(ids, secondIds);
                    assertEq(added, secondValue);
                    assertEq(newValue, targetValue + firstValue + secondValue);
                } else {
                    assertEq(ids, thirdIds);
                    assertEq(added, thirdValue);
                    assertEq(newValue, targetValue + firstValue + secondValue + thirdValue);
                }
                mergedSources[mergeCount++] = uint256(log.topics[2]);
            } else if (log.topics[0] == IShapePacks.MetadataUpdate.selector) {
                assertTrue(packLogStage == 2 || packLogStage == 7, "metadata order");
                assertEq(abi.decode(log.data, (uint256)), target);
                ++metadataCount;
            } else {
                assertTrue(log.topics[0] != IShapePacks.PackExtended.selector);
                assertTrue(log.topics[0] != IShapePacks.PackUnsealed.selector);
            }
            ++packLogStage;
        }
        assertEq(packLogStage, 8);
        assertEq(mergedSources, _three(first, second, third));
        assertEq(burnCount, 3);
        assertEq(mergeCount, 3);
        assertEq(metadataCount, 2, "one metadata update per call");
        assertEq(shapeTransferCount, 0);
    }

    function _three(uint256 a, uint256 b, uint256 c) private pure returns (uint256[] memory out) {
        out = new uint256[](3);
        out[0] = a;
        out[1] = b;
        out[2] = c;
    }

    function test_MergedTargetCanOpenAllShapes() public {
        uint256 target = _mintPack(alice, 1, 1);
        uint256 source = _mintPack(alice, 0, 3);
        uint256[] memory sourceIds = packs.contentsOf(source);
        vm.prank(alice);
        packs.mergePacks(target, ids1(source));
        vm.prank(alice);
        packs.open(target);
        for (uint256 i = 0; i < sourceIds.length; ++i) {
            assertEq(shapes.ownerOf(sourceIds[i]), alice);
            assertEq(packs.packOf(sourceIds[i]), 0);
        }
        assertEq(packs.totalSupply(), 0);
    }

    function test_MergedTargetRedeemsExactBacking() public {
        uint256 target = _mintPack(alice, 1, 1);
        uint256 source = _mintPack(alice, 0, 3);
        uint256 value = packs.valueOf(target) + packs.valueOf(source);
        uint256[] memory sourceIds = packs.contentsOf(source);
        vm.prank(alice);
        packs.mergePacks(target, ids1(source));

        uint256 beforeBalance = alice.balance;
        vm.prank(alice);
        packs.redeem(target);
        assertEq(alice.balance, beforeBalance + value);
        assertEq(packs.totalSupply(), 0);
        for (uint256 i = 0; i < sourceIds.length; ++i) {
            assertFalse(shapes.exists(sourceIds[i]));
            assertEq(packs.packOf(sourceIds[i]), 0);
        }
    }

    function test_MergedTargetCanUnsealAndClaimInChunks() public {
        uint256 target = _mintPack(alice, 1, 1);
        uint256 source = _mintPack(alice, 0, 3);
        vm.prank(alice);
        packs.mergePacks(target, ids1(source));
        uint256[] memory allIds = packs.contentsOf(target);

        vm.prank(alice);
        packs.unseal(target, alice);
        assertFalse(packs.exists(target));
        assertEq(packs.claimantOf(target), alice);
        for (uint256 i = 0; i < allIds.length; ++i) {
            assertEq(packs.packOf(allIds[i]), target);
        }

        vm.prank(alice);
        packs.claim(target, 2);
        assertEq(packs.contentsOf(target).length, allIds.length - 2);
        assertEq(shapes.ownerOf(allIds[allIds.length - 1]), alice);
        assertEq(shapes.ownerOf(allIds[allIds.length - 2]), alice);
        uint256 remainingValue;
        for (uint256 i = 0; i < allIds.length - 2; ++i) {
            remainingValue += shapes.backingOf(allIds[i]);
        }

        uint256 beforeBalance = alice.balance;
        vm.prank(alice);
        packs.claimEth(target, type(uint256).max, payable(alice));
        assertEq(alice.balance, beforeBalance + remainingValue);
        assertEq(packs.contentsOf(target).length, 0);
        assertEq(packs.claimantOf(target), address(0));
        for (uint256 i = 0; i < allIds.length; ++i) {
            assertEq(packs.packOf(allIds[i]), 0);
        }
    }

    function test_RejectsEmptySelfAndRepeatedSourcesAtomically() public {
        uint256 target = _mintPack(alice, 1, 1);
        uint256 source = _mintPack(alice, 1, 1);
        uint256[] memory sourceIds = packs.contentsOf(source);
        uint256 value = packs.valueOf(target);

        vm.expectRevert(IShapePacks.NoSourcePacks.selector);
        vm.prank(alice);
        packs.mergePacks(target, new uint256[](0));

        vm.expectRevert(abi.encodeWithSelector(IShapePacks.CannotMergePackIntoItself.selector, target));
        vm.prank(alice);
        packs.mergePacks(target, ids1(target));

        vm.expectRevert(abi.encodeWithSelector(IShapePacks.NotPackOwner.selector, source, alice));
        vm.prank(alice);
        packs.mergePacks(target, ids2(source, source));

        assertEq(packs.totalSupply(), 2);
        assertEq(packs.valueOf(target), value);
        assertEq(packs.ownerOf(source), alice);
        assertEq(packs.contentsOf(source), sourceIds);
        assertEq(packs.packOf(sourceIds[0]), source);
    }

    function test_RequiresOwnerNotApprovalAndRejectsDeadPacks() public {
        uint256 target = _mintPack(alice, 1, 1);
        uint256 source = _mintPack(alice, 1, 1);
        uint256 other = _mintPack(bob, 1, 1);
        vm.prank(alice);
        packs.setApprovalForAll(bob, true);

        vm.expectRevert(abi.encodeWithSelector(IShapePacks.NotPackOwner.selector, target, bob));
        vm.prank(bob);
        packs.mergePacks(target, ids1(source));

        vm.expectRevert(abi.encodeWithSelector(IShapePacks.NotPackOwner.selector, other, alice));
        vm.prank(alice);
        packs.mergePacks(target, ids1(other));

        vm.prank(alice);
        packs.unseal(source, alice);
        vm.expectRevert(abi.encodeWithSelector(IShapePacks.NotPackOwner.selector, source, alice));
        vm.prank(alice);
        packs.mergePacks(target, ids1(source));

        vm.expectRevert(abi.encodeWithSelector(IShapePacks.NotPackOwner.selector, source, alice));
        vm.prank(alice);
        packs.mergePacks(source, ids1(target));
    }
}
