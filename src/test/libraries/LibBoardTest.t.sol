// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Letter} from "../../common/Letter.sol";
import {Position, Direction} from "../../common/Play.sol";
import {Merkle} from "../murky/src/Merkle.sol";
import {LibBoard} from "../../libraries/LibBoard.sol";
import "../../common/Errors.sol";
import "forge-std/Test.sol";

contract LibBoardTest is Test {
    bytes32[] public words;
    Merkle private m; // Store here to avoid stack too deep errors

    function setUp() public {
        m = new Merkle();
        words.push(
            keccak256(
                abi.encodePacked([Letter.W, Letter.O, Letter.R, Letter.D])
            )
        ); // test
        words.push(
            keccak256(
                abi.encodePacked([Letter.T, Letter.A, Letter.L, Letter.K])
            )
        ); // talk
    }

    function testVerifyWordProof() public view {
        Letter[] memory word = new Letter[](4);
        word[0] = Letter.W;
        word[1] = Letter.O;
        word[2] = Letter.R;
        word[3] = Letter.D;
        LibBoard.verifyWordProof(word, m.getProof(words, 0), m.getRoot(words));
    }

    function testGetRewardPerEmptyTile(
        uint8 numEmpty,
        uint256 rewardFraction,
        uint256 value
    ) public {
        // Reasonable values for numEmpty, because this is for words in english
        vm.assume(numEmpty > 0 && numEmpty < 100);
        vm.assume(rewardFraction > 0);
        Letter[] memory word = new Letter[](numEmpty + 1);
        word[0] = Letter.A;
        for (uint256 i = 0; i < numEmpty; i++) {
            word[i + 1] = Letter.EMPTY;
        }
        assertTrue(
            LibBoard.getRewardPerEmptyTile(word, rewardFraction, value) ==
                value / numEmpty / rewardFraction
        );
    }

    function testGetLetterPosition(int32 letterOffset, Position memory position)
        public
    {
        // Assume this game doesn't go CRAZY CRAZY
        vm.assume(letterOffset < 1000000 && letterOffset > -1000000);
        vm.assume(position.x < 1000000 && position.x > -1000000);
        vm.assume(position.y < 1000000 && position.y > -1000000);

        Position memory xPosition = LibBoard.getLetterPosition(
            letterOffset,
            position,
            Direction.LEFT_TO_RIGHT
        );
        Position memory yPosition = LibBoard.getLetterPosition(
            letterOffset,
            position,
            Direction.TOP_TO_BOTTOM
        );
        assertTrue(
            (xPosition.x == position.x + letterOffset) &&
                (xPosition.y == position.y)
        );
        assertTrue(
            (yPosition.x == position.x) &&
                (yPosition.y == position.y + letterOffset)
        );
    }
}
