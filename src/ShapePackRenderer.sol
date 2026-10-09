// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {FixedPoint} from "shapes/lib/FixedPoint.sol";
import {IShapeCollection} from "shapes/interfaces/IShapeCollection.sol";
import {IShapeRenderer} from "shapes/interfaces/IShapeRenderer.sol";
import {IShapes} from "shapes/interfaces/IShapes.sol";
import {ShapeState} from "shapes/ShapeTypes.sol";

import {IShapePackRenderer, PackRenderInput} from "./interfaces/IShapePackRenderer.sol";

/// @title ShapePackRenderer
/// @notice Draws a pack as a fan of its highest-backed Shapes and describes it as JSON.
/// @dev View-only logic. Its only immutable configuration is the Shapes address; the renderer is
///      read from Shapes on every call, so pack art follows Shapes' art. Each 2000x2800 Shapes
///      SVG is fitted without distortion into a portrait card on a 3840 square canvas. Callers
///      supply JSON-safe copy; `ShapePacks` validates it when it is set.
contract ShapePackRenderer is IShapePackRenderer, IERC165 {
    uint256 private constant CANVAS = 3840;
    uint256 private constant CENTER = CANVAS / 2;
    uint256 private constant MAX_CARDS = 11;

    struct CardSlot {
        uint256 x;
        uint256 y;
        uint256 width;
        uint256 height;
        string angle;
    }

    /// @inheritdoc IShapePackRenderer
    address public immutable shapes;

    error NotAContract(address target);

    constructor(address shapes_) {
        if (shapes_.code.length == 0) revert NotAContract(shapes_);
        shapes = shapes_;
    }

    /* ------------------------------- metadata ------------------------------- */

    /// @inheritdoc IShapePackRenderer
    function tokenURI(PackRenderInput calldata input) external view returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(_json(input)))));
    }

    /// @inheritdoc IShapePackRenderer
    function metadataJSON(PackRenderInput calldata input) external view returns (string memory) {
        return _json(input);
    }

    /// @inheritdoc IShapePackRenderer
    function image(PackRenderInput calldata input) external view returns (string memory) {
        return _image(input);
    }

    /// @inheritdoc IShapePackRenderer
    function contractURI(string calldata name, string calldata description, bytes32 seed)
        external
        view
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"',
                        name,
                        '","description":"',
                        description,
                        '","image":"data:image/svg+xml;base64,',
                        Base64.encode(bytes(_collectionImage(seed))),
                        '"}'
                    )
                )
            )
        );
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IShapePackRenderer).interfaceId;
    }

    /// @dev name, description and image, then the attribute list.
    function _json(PackRenderInput calldata input) private view returns (string memory) {
        return string(
            abi.encodePacked(
                '{"name":"',
                input.tokenNamePrefix,
                FixedPoint.toString(input.packId),
                '","description":"',
                input.description,
                " ",
                _makeup(input),
                '","image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(_image(input))),
                '","attributes":[',
                _attributes(input),
                "]}"
            )
        );
    }

    /// @dev `3 x 0.01 ETH, 1 x 0.05 ETH. 0.08 ETH total.` The ASCII `x` keeps the JSON byte-safe.
    function _makeup(PackRenderInput calldata input) private pure returns (bytes memory out) {
        uint256 n = input.counts.length;
        bool first = true;
        for (uint256 d = 0; d < n; ++d) {
            uint32 count = input.counts[d];
            if (count == 0) continue;
            out = abi.encodePacked(
                out,
                first ? "" : ", ",
                FixedPoint.toString(count),
                " x ",
                FixedPoint.fmt(input.denominations[d]),
                " ETH"
            );
            first = false;
        }
        out = abi.encodePacked(out, ". ", FixedPoint.fmt(input.valueWei), " ETH total.");
    }

    /// @dev Shapes, Value, Units, one row per held denomination, Source, Creator.
    function _attributes(PackRenderInput calldata input) private pure returns (bytes memory out) {
        out = abi.encodePacked(
            '{"trait_type":"Shapes","value":',
            FixedPoint.toString(input.shapeCount),
            '},{"trait_type":"Value","value":"',
            FixedPoint.fmt(input.valueWei),
            ' ETH"},{"display_type":"number","trait_type":"Units","value":',
            FixedPoint.toString(input.valueWei / input.unitWei),
            "}"
        );
        uint256 n = input.counts.length;
        for (uint256 d = 0; d < n; ++d) {
            uint32 count = input.counts[d];
            if (count == 0) continue;
            out = abi.encodePacked(
                out,
                ',{"trait_type":"',
                FixedPoint.fmt(input.denominations[d]),
                ' ETH","value":',
                FixedPoint.toString(count),
                "}"
            );
        }
        out = abi.encodePacked(
            out,
            ',{"trait_type":"Source","value":"',
            _source(input.mintedCount, input.shapeCount),
            '"},{"trait_type":"Creator","value":"',
            Strings.toChecksumHexString(input.creator),
            '"}'
        );
    }

    /// @dev Minted when the pack minted every Shape, Packed when it minted none, else Mixed.
    function _source(uint256 mintedCount, uint256 shapeCount) private pure returns (string memory) {
        if (mintedCount == shapeCount) return "Minted";
        if (mintedCount == 0) return "Packed";
        return "Mixed";
    }

    /* -------------------------------- images -------------------------------- */

    /// @dev Rank zero is centred except in balanced even fans of up to eight cards.
    function _image(PackRenderInput calldata input) private view returns (string memory) {
        IShapeRenderer renderer = IShapeRenderer(IShapes(shapes).renderer());
        uint256 n = input.topCards.length;
        if (n > MAX_CARDS) n = MAX_CARDS;
        string[] memory cards = new string[](n);
        for (uint256 i = 0; i < n; ++i) {
            cards[i] = _artwork(renderer, input.topCards[i]);
        }
        return _stack(cards);
    }

    /// @dev Three illustrative cards in the same fan. A collection-less Shapes falls back to
    ///      an empty black card; no external art is available in that configuration.
    function _collectionImage(bytes32 seed) private view returns (string memory) {
        address collection = IShapes(shapes).collection();
        if (collection == address(0)) return _stack(new string[](0));
        string[] memory cards = new string[](3);
        uint8[3] memory denoms = [uint8(4), 2, 0];
        for (uint256 i = 0; i < 3; ++i) {
            cards[i] = IShapeCollection(collection).cardFor(keccak256(abi.encodePacked(seed, i)), denoms[i]);
        }
        return _stack(cards);
    }

    /// @dev The Shapes artwork for one card: sampled modules when present, else the seed.
    function _artwork(IShapeRenderer renderer, ShapeState calldata state)
        private
        pure
        returns (string memory)
    {
        if (state.modules.length != 0) {
            return renderer.renderSVGSampled(state.modules, state.faceValueWei, state.isBlack, state.inkGene);
        }
        return renderer.renderSVG(state.seed, state.faceValueWei, state.isBlack, state.inkGene);
    }

    /// @dev Draw lower-value cards first, so the highest-backed face always sits on top.
    function _stack(string[] memory cards) private pure returns (string memory) {
        uint256 n = cards.length;
        if (n > MAX_CARDS) n = MAX_CARDS;
        bytes memory body = _open(n == 0 ? 1 : n);
        if (n == 0) {
            body = abi.encodePacked(body, _card(0, 1, ""));
        } else {
            for (uint256 i = n; i > 0; --i) {
                body = abi.encodePacked(body, _card(i - 1, n, cards[i - 1]));
            }
        }
        return string(abi.encodePacked(body, "</svg>"));
    }

    /// @dev The Draw index hero uses 75% inner faces, 58% outer faces and tilts that
    ///      ease by two degrees per pair. Even fans through eight use a scaled two-card
    ///      centre; other fans keep their existing centre and spacing.
    function _slot(uint256 rank, uint256 n) private pure returns (CardSlot memory slot) {
        if (n <= 8 && n % 2 == 0) return _evenSlot(rank, n);

        uint256 pairs = n / 2;
        uint256 stepPercent = 65 - pairs * 5;
        uint256 frontWidth = pairs == 0 ? 1600 : (CANVAS - 240) * 100 / (pairs * stepPercent * 2 + 58);
        if (frontWidth > 1600) frontWidth = 1600;
        uint256 frontHeight = frontWidth * 7 / 5;
        uint256 baseline = (CANVAS + frontHeight) / 2;
        if (rank == 0) {
            slot.width = frontWidth;
            slot.height = frontHeight;
            slot.x = CENTER - frontWidth / 2;
            slot.y = baseline - frontHeight;
            slot.angle = "-1";
            return slot;
        }
        uint256 pair = (rank + 1) / 2;
        slot.width = frontWidth * (pair == 1 ? 75 : 58) / 100;
        slot.height = slot.width * 7 / 5;
        uint256 firstStep = frontWidth * stepPercent * (pairs == 1 ? 4 : 3) / 400;
        uint256 offset = firstStep;
        if (pair > 1) offset += firstStep * 9 / 16;
        if (pair > 2) offset += (pair - 2) * firstStep;
        bool right = rank % 2 == 1;
        slot.x = right ? CENTER + offset - slot.width / 2 : CENTER - offset - slot.width / 2;
        slot.y = baseline - slot.height;
        slot.angle = right ? FixedPoint.toString(11 - pair * 2) : _neg(13 - pair * 2);
    }

    /// @dev Keep the two-card pair's width-to-spacing ratio at every even size. The
    ///      first outer pair stays put; the gap into tier three uses 56.25% of that
    ///      step, then later gaps retain their previous spacing.
    function _evenSlot(uint256 rank, uint256 n) private pure returns (CardSlot memory slot) {
        uint256 pairs = n / 2;
        uint256 frontWidth =
            n == 2 ? 1450 : (CANVAS - 400) * 100 / (2 * (39 + (pairs - 1) * 55) + (pairs == 2 ? 75 : 58));
        uint256 pair = rank / 2;
        bool right = rank % 2 == 1;
        if (pair == 0) slot.width = frontWidth;
        else if (pair == 1) slot.width = frontWidth * 75 / 100;
        else slot.width = frontWidth * 58 / 100;
        slot.height = slot.width * 7 / 5;
        uint256 outerStep = frontWidth * 165 / 400;
        uint256 offset = frontWidth * 570 / 1450;
        if (pair != 0) {
            offset += outerStep;
            if (pair > 1) offset += outerStep * 9 / 16;
            if (pair > 2) offset += (pair - 2) * (outerStep * 3 / 4);
        }
        slot.x = right ? CENTER + offset - slot.width / 2 : CENTER - offset - slot.width / 2;
        slot.y = (CANVAS + frontWidth * 7 / 5) / 2 - slot.height;
        if (pair == 0) slot.angle = right ? "5" : "-5";
        else slot.angle = right ? FixedPoint.toString(11 - pair * 2) : _neg(13 - pair * 2);
    }

    /// @dev Transparent canvas, shadows and local rounded clip paths for each Shape SVG.
    function _open(uint256 cardCount) private pure returns (bytes memory out) {
        out = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 3840 3840" width="3840" height="3840"'
            ' shape-rendering="geometricPrecision"><defs>'
            '<filter id="d" x="-15%" y="-15%" width="130%" height="130%">'
            '<feDropShadow dx="0" dy="0" stdDeviation="44" flood-color="#000" flood-opacity="0.22"/></filter>'
        );
        for (uint256 i = 0; i < cardCount; ++i) {
            out = abi.encodePacked(
                out,
                '<clipPath id="c',
                FixedPoint.toString(i),
                '">',
                '<rect width="2000" height="2800" rx="40"/>',
                "</clipPath>"
            );
        }
        out = abi.encodePacked(out, "</defs>");
    }

    /// @dev A Shapes SVG sits in a 2000x2800 local viewBox, scaled to the slot without distortion.
    function _card(uint256 rank, uint256 n, string memory art) private pure returns (bytes memory) {
        CardSlot memory slot = _slot(rank, n);
        return abi.encodePacked(
            '<g transform="translate(',
            FixedPoint.toString(slot.x),
            ",",
            FixedPoint.toString(slot.y),
            ") rotate(",
            slot.angle,
            " ",
            FixedPoint.toString(slot.width / 2),
            " ",
            FixedPoint.toString(slot.height / 2),
            ')"><rect width="',
            FixedPoint.toString(slot.width),
            '" height="',
            FixedPoint.toString(slot.height),
            '" rx="',
            FixedPoint.toString(slot.width / 50),
            '" fill="#000" filter="url(#d)"/><svg width="',
            FixedPoint.toString(slot.width),
            '" height="',
            FixedPoint.toString(slot.height),
            '" viewBox="0 0 2000 2800"><g clip-path="url(#c',
            FixedPoint.toString(rank),
            ')">',
            art,
            "</g></svg></g>"
        );
    }

    /// @dev `-magnitude`, or `0` for zero, written through the unsigned formatter.
    function _neg(uint256 magnitude) private pure returns (string memory) {
        if (magnitude == 0) return "0";
        return string(abi.encodePacked("-", FixedPoint.toString(magnitude)));
    }
}
