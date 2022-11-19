// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Letter} from "../common/Letter.sol";
import {Position, Direction} from "../common/Play.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {TileComponent, ID as TileComponentID} from "../components/TileComponent.sol";
import "../common/Errors.sol";

library LibBoard {
    /// @notice Verifies a Merkle proof to check if a given word is in the dictionary.
    function verifyWordProof(
        Letter[] memory word,
        bytes32[] memory proof,
        bytes32 merkleRoot
    ) internal pure {
        bytes32 leaf = keccak256(abi.encodePacked(word));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        if (!isValidLeaf) revert InvalidWord();
    }

    /// @notice Get the amount of rewards paid to every empty tile in the word.
    function getRewardPerEmptyTile(Letter[] memory word, uint256 rewardFraction, uint256 value)
        internal
        pure
        returns (uint256)
    {
        uint256 numEmptyTiles;
        for (uint32 i = 0; i < word.length; i++) {
            if (word[i] == Letter.EMPTY) numEmptyTiles++;
        }
        // msg.value / rewardFraction is total to be paid out in rewards, split across numEmptyTiles
        return (value / rewardFraction) / numEmptyTiles;
    }

    /// @notice Gets the position of a letter in a word given an offset and a direction.
    /// @dev Useful for looping through words.
    /// @param letterOffset The offset of the position from the start position.
    /// @param position The start position of the word.
    /// @param direction The direction the word is being played in.
    function getLetterPosition(
        int32 letterOffset,
        Position memory position,
        Direction direction
    ) internal pure returns (Position memory) {
        if (direction == Direction.LEFT_TO_RIGHT) {
            return Position(position.x + letterOffset, position.y);
        } else {
            return Position(position.x, position.y + letterOffset);
        }
    }

    /// @notice Gets the positions OUTSIDE a boundary on the boundary axis.
    /// @dev Useful for checking if a boundary is valid.
    /// @param letterPosition The start position of the letter for which the boundary is for.
    /// @param direction The direction the original word (not the boundary) is being played in.
    /// @param positive The distance the bound spans in the positive direction.
    /// @param negative The distance the bound spans in the negative direction.
    function getOutsideBoundPositions(
        Position memory letterPosition,
        Direction direction,
        uint32 positive,
        uint32 negative
    ) internal pure returns (Position memory, Position memory) {
        Position memory start = Position(letterPosition.x, letterPosition.y);
        Position memory end = Position(letterPosition.x, letterPosition.y);
        if (direction == Direction.LEFT_TO_RIGHT) {
            start.y -= (int32(negative) + 1);
            end.y += (int32(positive) + 1);
        } else {
            start.x -= (int32(negative) + 1);
            end.x += (int32(positive) + 1);
        }
        return (start, end);
    }

    /// @notice Gets the word inside a given boundary and checks to make sure there are no empty letters in the bound.
    /// @dev Assumes that the word being made this round has already been played on board
    function getWordInBoundsChecked(
        Position memory letterPosition,
        Direction direction,
        uint32 positive,
        uint32 negative,
        TileComponent tiles
    ) internal view returns (Letter[] memory) {
        uint32 wordLength = positive + negative + 1;
        Letter[] memory word = new Letter[](wordLength);
        Position memory position;
        // Start at edge of negative bound
        if (direction == Direction.LEFT_TO_RIGHT) {
            position = LibBoard.getLetterPosition(
                -1 * int32(negative),
                letterPosition,
                Direction.TOP_TO_BOTTOM
            );
        } else {
            position = LibBoard.getLetterPosition(
                -1 * int32(negative),
                letterPosition,
                Direction.LEFT_TO_RIGHT
            );
        }
        for (uint32 i = 0; i < wordLength; i++) {
            word[i] = tiles.getValueAtPosition(position).letter;
            if (word[i] == Letter.EMPTY) revert EmptyLetterInBounds();
            if (direction == Direction.LEFT_TO_RIGHT) {
                position.y += 1;
            } else {
                position.x += 1;
            }
        }
        return word;
    }
}
