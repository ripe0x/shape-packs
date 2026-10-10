// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IShapes} from "shapes/interfaces/IShapes.sol";

import {IShapePacks, PackState} from "../src/interfaces/IShapePacks.sol";

/// @notice Mints six sample packs with 1, 2, 3, 6, 9 and 12 Shapes on Sepolia.
/// @dev The wrapper selects a recorded collection and signer. The empty-collection check
///      stops accidental replay after any pack has been created.
contract MintSamples is Script {
    /// @notice Quotes and creates six packs in the selected Sepolia collection.
    function run() external {
        require(block.chainid == 11155111, "Sepolia only");
        address packsAddress = vm.envAddress("PACKS");
        address shapesAddress = vm.envAddress("SHAPES");
        address recipient = vm.envAddress("EXPECTED_SIGNER");
        IShapePacks packs = IShapePacks(packsAddress);
        IShapes shapes = IShapes(shapesAddress);
        require(packs.shapes() == shapesAddress, "wrong Shapes");
        require(packs.totalMinted() == 0, "collection is no longer empty");
        require(packs.previewCardLimit() == 12, "unexpected preview limit");
        require(shapes.denominationCount() >= 3, "missing denominations");
        require(block.timestamp >= shapes.mintStart(), "Shapes mint not open");

        uint8[6] memory sizes = [uint8(1), 2, 3, 6, 9, 12];
        uint256[] memory noPulledShapes = new uint256[](0);

        vm.startBroadcast();
        (, address broadcaster,) = vm.readCallers();
        require(broadcaster == recipient, "wrong broadcaster");
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
            require(packs.ownerOf(packId) == recipient, "wrong pack owner");
            require(state.shapeIds.length == size && state.valueWei == backing, "wrong pack state");
        }
        vm.stopBroadcast();
    }
}
