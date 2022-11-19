// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {BoardSystem, ID as BoardSystemID, Position} from "../../systems/BoardSystem.sol";
import {TileComponent, ID as TileComponentID} from "../../components/TileComponent.sol";
import {ScoreComponent, ID as ScoreComponentID} from "../../components/ScoreComponent.sol";
import {LetterCountComponent, ID as LetterCountComponentID} from "../../components/LetterCountComponent.sol";

import "../MudTest.t.sol";

import {Letter} from "../../common/Letter.sol";
import {Tile} from "../../common/Tile.sol";
import {Score} from "../../common/Score.sol";
import {Direction, Bounds, Position} from "../../common/Play.sol";
import {Merkle} from "../murky/src/Merkle.sol";
import {console} from "forge-std/console.sol";
import "../../common/Errors.sol";

contract FuzzBoardTest is MudTest {
    bytes32[] public words;
    Merkle private m; // Store here to avoid stack too deep errors

    modifier setupBoard(address deployer) {
        vm.deal(deployer, 10 ether);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));
        boardSystem.setMerkleRoot(m.getRoot(words));
        boardSystem.setupInitialGrid();
        _;
    }

    function setUp() public override {
        super.setUp();
        m = new Merkle();
        words.push(
            keccak256(
                abi.encodePacked([Letter.T, Letter.E, Letter.S, Letter.T])
            )
        ); // test
        words.push(
            keccak256(
                abi.encodePacked([Letter.T, Letter.A, Letter.L, Letter.K])
            )
        ); // talk
        words.push(
            keccak256(
                abi.encodePacked([Letter.T, Letter.I, Letter.C, Letter.K])
            )
        ); // tick
    }

    function testFailNotConnectingWord(
        Position memory startPosition,
        Direction direction
    ) public prank(deployer) setupBoard(deployer) {
        // Should never be able to play a whole word
        Letter[] memory tick = new Letter[](4);
        tick[0] = Letter.T;
        tick[1] = Letter.I;
        tick[2] = Letter.C;
        tick[3] = Letter.K;
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        boardSystem.executeTyped{value: 1 ether}(
            tick,
            m.getProof(words, 2),
            startPosition,
            direction,
            Bounds(new uint32[](4), new uint32[](4), new bytes32[][](4))
        );
    }

    function testFailNotConnectingWordConstrained(
        Position memory startPosition,
        Direction direction
    ) public prank(deployer) setupBoard(deployer) {
        vm.assume(startPosition.x < 20 && startPosition.x > -20);
        vm.assume(startPosition.y < 20 && startPosition.y > -20);

        // Same test as above, but with words on board and contstrained position
        Letter[] memory tickEmpty = new Letter[](4);
        tickEmpty[0] = Letter.T;
        tickEmpty[1] = Letter.EMPTY;
        tickEmpty[2] = Letter.C;
        tickEmpty[3] = Letter.K;
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        // This passes
        boardSystem.executeTyped{value: 1 ether}(
            tickEmpty,
            m.getProof(words, 2),
            Position(0, -1),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](4), new uint32[](4), new bytes32[][](4))
        );

        // This should not
        Letter[] memory tick = new Letter[](4);
        tick[0] = Letter.T;
        tick[1] = Letter.I;
        tick[2] = Letter.C;
        tick[3] = Letter.K;

        boardSystem.executeTyped{value: 1 ether}(
            tick,
            m.getProof(words, 2),
            startPosition,
            direction,
            Bounds(new uint32[](4), new uint32[](4), new bytes32[][](4))
        );
    }

    function testFailImpossibleMove(
        Position memory startPosition,
        Direction direction
    ) public prank(deployer) setupBoard(deployer) {
        // Constrain position to be reasonable
        vm.assume(startPosition.x < 10 && startPosition.x > -10);
        vm.assume(startPosition.y < 10 && startPosition.y > -10);

        // This should never work, since the letter C is not in INFINITE, the default work
        Letter[] memory tick = new Letter[](4);
        tick[0] = Letter.T;
        tick[1] = Letter.I;
        tick[2] = Letter.EMPTY;
        tick[3] = Letter.K;

        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        boardSystem.executeTyped{value: 1 ether}(
            tick,
            m.getProof(words, 2),
            startPosition,
            direction,
            Bounds(new uint32[](4), new uint32[](4), new bytes32[][](4))
        );
    }

    function testFailInvalidMove(
        uint8[6] memory rawWord,
        Position memory startPosition,
        Direction direction,
        Bounds memory bounds
    ) public prank(deployer) setupBoard(deployer) {
        // Assume this is a word and not a word that is in our dictionary
        for (uint256 i = 0; i < rawWord.length; i++) {
            vm.assume(uint8(rawWord[i]) < 27);
        }
        vm.assume(rawWord[0] != uint8(Letter.T));
        // Assume some basic facts about well formed bounds
        vm.assume(
            rawWord[0] != uint8(Letter.R) && rawWord[0] != uint8(Letter.F)
        );
        vm.assume(bounds.positive.length == bounds.negative.length);
        vm.assume(bounds.proofs.length == bounds.positive.length);

        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        Letter[] memory word = new Letter[](6);
        word[0] = Letter(rawWord[0]);
        word[1] = Letter(rawWord[1]);
        word[2] = Letter(rawWord[2]);
        word[3] = Letter(rawWord[3]);
        word[4] = Letter(rawWord[4]);
        word[5] = Letter(rawWord[5]);

        // This should always fail
        boardSystem.executeTyped{value: 1 ether}(
            word,
            m.getProof(words, 0),
            startPosition,
            direction,
            bounds
        );
    }
}
