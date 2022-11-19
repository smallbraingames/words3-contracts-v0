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

contract DoubleCountBoardTest is MudTest {
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
                abi.encodePacked([Letter.I, Letter.A, Letter.A, Letter.A])
            )
        ); // IAAA (a made up word to test double counting)
        words.push(
            keccak256(
                abi.encodePacked(
                    [Letter.Z, Letter.N, Letter.Z, Letter.Z, Letter.Z]
                )
            )
        ); // ZNZZZ (another made up word to test double counting)
        words.push(keccak256(abi.encodePacked([Letter.A, Letter.Z]))); // AZ (word to test double counting)
    }

    function testTripleDoubleCounting() public setupBoard(deployer) {
        // Test if the below grid can be played in the order IAAA, ZNZZZ
        /*
              Z
            I N F I N I T E
            A Z  
            A Z   
            A Z  
         */
        // The words AZ should be counted three times as well as ZNZZZ
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));
        ScoreComponent scores = ScoreComponent(component(ScoreComponentID));

        // Play IAAA
        Letter[] memory iaaa = new Letter[](4);
        iaaa[0] = Letter.EMPTY;
        iaaa[1] = Letter.A;
        iaaa[2] = Letter.A;
        iaaa[3] = Letter.A;

        boardSystem.executeTyped{value: 1 ether}(
            iaaa,
            m.getProof(words, 0),
            Position(0, 0),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](4), new uint32[](4), new bytes32[][](4))
        );

        // Switch to playerOne
        address playerOne = address(12332);
        vm.startPrank(playerOne);
        vm.deal(playerOne, 2 ether);

        // Play ZDZZZ
        Letter[] memory znzzz = new Letter[](5);
        znzzz[0] = Letter.Z;
        znzzz[1] = Letter.EMPTY;
        znzzz[2] = Letter.Z;
        znzzz[3] = Letter.Z;
        znzzz[4] = Letter.Z;

        uint32[] memory negative = new uint32[](5);
        negative[2] = 1;
        negative[3] = 1;
        negative[4] = 1;

        bytes32[][] memory proofs = new bytes32[][](5);
        bytes32[] memory azProof = m.getProof(words, 2);
        proofs[2] = azProof;
        proofs[3] = azProof;
        proofs[4] = azProof;

        boardSystem.executeTyped{value: 1 ether}(
            znzzz,
            m.getProof(words, 1),
            Position(1, -1),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](5), negative, proofs)
        );

        // Check accounting
        Score memory contractScore = scores.getValueAtAddress(address(this));
        Score memory playerOneScore = scores.getValueAtAddress(playerOne);

        // just played iaaa
        assertTrue(contractScore.score == 4);
        assertTrue(contractScore.rewards == 0);
        assertTrue(playerOneScore.spent == 1 ether);
        // played (znzzz = 41) + (az = 11) * 3 = 74
        assertTrue(playerOneScore.score == 74);
        assertTrue(playerOneScore.rewards == 0);
        assertTrue(playerOneScore.spent == 1 ether);

        // Check payout
        vm.warp(block.timestamp + 1000000);
        uint256 prevBalance = address(playerOne).balance;
        boardSystem.claimPayout();
        uint256 postBalance = address(playerOne).balance;
        assertTrue(
            (postBalance - prevBalance) ==
                (uint256(2 ether - 1 ether / 4 - 1 ether / 4) * 74) / 78
        );
    }
}
