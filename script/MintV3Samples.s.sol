// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IShapes} from "shapes/interfaces/IShapes.sol";

import {IShapePacks, PackState} from "../src/interfaces/IShapePacks.sol";

/// @notice Mints six fresh Sepolia v3 packs with 1, 2, 3, 6, 9 and 12 Shapes.
/// @dev Each pack mints its Shapes from ETH and goes to the broadcaster. The empty-collection
///      check stops accidental replay after any pack has been created.
contract MintV3Samples is Script {
    address private constant SHAPES = 0x6C2F9c00F44FBBF141dD166979903004b80D5f99;
    address private constant PACKS = 0xd1CfC13aBcBB370d381aC192Aeb6F2E1b414022A;
    address private constant RECIPIENT = 0xCB43078C32423F5348Cab5885911C3B5faE217F9;

    /// @notice Quotes and creates the six packs against the deployed Sepolia collection.
    function run() external {
        require(block.chainid == 11155111, "Sepolia only");
        IShapePacks packs = IShapePacks(PACKS);
        IShapes shapes = IShapes(SHAPES);
        require(packs.shapes() == SHAPES, "wrong Shapes");
        require(packs.totalMinted() == 0, "collection is no longer empty");
        require(packs.previewCardLimit() == 12, "unexpected preview limit");
        require(shapes.denominationCount() >= 3, "missing denominations");
        require(block.timestamp >= shapes.mintStart(), "Shapes mint not open");

        uint8[6] memory sizes = [uint8(1), 2, 3, 6, 9, 12];
        uint256[] memory noPulledShapes = new uint256[](0);

        vm.startBroadcast();
        (, address broadcaster,) = vm.readCallers();
        require(broadcaster == RECIPIENT, "wrong broadcaster");
        for (uint256 i = 0; i < sizes.length; ++i) {
            uint32[] memory counts = new uint32[](shapes.denominationCount());
            uint8 size = sizes[i];
            if (size == 1) {
                counts[1] = 1;
            } else if (size == 2) {
                counts[0] = 1;
                counts[1] = 1;
            } else {
                counts[0] = uint32(size - 2);
                counts[1] = 1;
                counts[2] = 1;
            }

            (uint256 backing,, uint256 payment, uint256 count) = packs.quoteMint(counts);
            require(count == size && backing >= packs.MIN_PACK_VALUE(), "invalid sample makeup");
            uint256 packId = packs.createPack{value: payment}(noPulledShapes, counts);
            PackState memory state = packs.packState(packId);
            require(packs.ownerOf(packId) == RECIPIENT, "wrong pack owner");
            require(state.shapeIds.length == size && state.valueWei == backing, "wrong pack state");
        }
        vm.stopBroadcast();
    }
}
