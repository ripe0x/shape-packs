// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ShapeState} from "shapes/ShapeTypes.sol";

/// @notice The pack data passed to a renderer by `ShapePacks`, assembled from its storage and Shapes.
struct PackRenderInput {
    uint256 packId;
    uint256 shapeCount;
    uint256 valueWei;
    uint256 unitWei;
    uint32[] counts; // Shapes per ladder index, length == denomination count
    uint256[] denominations; // wei per ladder index, same length
    uint256 mintedCount; // Shapes the pack minted itself; shapeCount - mintedCount were pulled
    address creator;
    ShapeState[] topCards; // up to the admin-set preview limit, highest backing first
    string tokenNamePrefix;
    string description;
}

/// @title IShapePackRenderer
/// @notice Presentation for Shape Packs: the stack image, the metadata JSON, and the
///         collection-level metadata.
/// @dev Rendering methods are views. The current implementation reads the Shapes renderer live,
///      so card art follows the onchain Shapes renderer.
interface IShapePackRenderer {
    /// @notice The Shapes token whose renderer draws the cards.
    function shapes() external view returns (address);

    /// @notice `data:application/json;base64,...` for one pack.
    function tokenURI(PackRenderInput calldata input) external view returns (string memory);

    /// @notice The raw metadata JSON for one pack.
    function metadataJSON(PackRenderInput calldata input) external view returns (string memory);

    /// @notice The raw SVG for one pack. The current renderer draws up to twelve supplied faces.
    function image(PackRenderInput calldata input) external view returns (string memory);

    /// @notice `data:application/json;base64,...` for the collection.
    /// @param name The collection's ERC-721 name.
    /// @param description The shared description.
    /// @param seed Entropy for the illustrative stack; `ShapePacks` passes a per-block value.
    function contractURI(string calldata name, string calldata description, bytes32 seed)
        external
        view
        returns (string memory);
}
