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

contract GridBoardTest is MudTest {
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
                abi.encodePacked(
                    [Letter.F, Letter.I, Letter.T, Letter.T, Letter.E, Letter.D]
                )
            )
        ); // fitted
        words.push(
            keccak256(
                abi.encodePacked(
                    [Letter.R, Letter.A, Letter.F, Letter.T, Letter.E, Letter.R]
                )
            )
        ); // rafter
        words.push(
            keccak256(
                abi.encodePacked(
                    [
                        Letter.R,
                        Letter.A,
                        Letter.F,
                        Letter.T,
                        Letter.E,
                        Letter.R,
                        Letter.S
                    ]
                )
            )
        ); // rafters
        words.push(
            keccak256(
                abi.encodePacked(
                    [Letter.F, Letter.A, Letter.D, Letter.E, Letter.S]
                )
            )
        ); // fades
    }

    function testScoreDoubleCount()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        // Test if the below grid can be played in the order FITTED, RAFTER, FADES
        /*      R
            F   A
            I N F I N I T E
            T   T  
            T   E  
            E   R   
        F A D E S
         */
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));
        ScoreComponent scores = ScoreComponent(component(ScoreComponentID));

        // address playerOne = address(1);
        // address playerTwo = address(1);
        // vm.deal(playerOne, 1 ether);
        // vm.deal(playerTwo, 1 ether);
        // //vm.prank(playerOne);

        // Play FITTED
        Letter[] memory fitted = new Letter[](6);
        fitted[0] = Letter.F;
        fitted[1] = Letter.EMPTY;
        fitted[2] = Letter.T;
        fitted[3] = Letter.T;
        fitted[4] = Letter.E;
        fitted[5] = Letter.D;

        boardSystem.executeTyped{value: 1 ether}(
            fitted,
            m.getProof(words, 0),
            Position(0, -1),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](6), new uint32[](6), new bytes32[][](6))
        );

        Score memory fittedScore = scores.getValueAtAddress(deployer);
        assertTrue(fittedScore.score == 10);
        assertTrue(fittedScore.rewards == 0);
        assertTrue(fittedScore.spent == 1 ether);

        // Play RAFTER
        Letter[] memory rafter = new Letter[](6);
        rafter[0] = Letter.R;
        rafter[1] = Letter.A;
        rafter[2] = Letter.EMPTY;
        rafter[3] = Letter.T;
        rafter[4] = Letter.E;
        rafter[5] = Letter.R;

        boardSystem.executeTyped{value: 1 ether}(
            rafter,
            m.getProof(words, 1),
            Position(2, -2),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](6), new uint32[](6), new bytes32[][](6))
        );

        Score memory rafterScore = scores.getValueAtAddress(deployer);
        assertTrue(rafterScore.score == fittedScore.score + 9);
        assertTrue(rafterScore.rewards == 0);
        assertTrue(rafterScore.spent == 2 ether);

        // Play FADES
        Letter[] memory fades = new Letter[](5);
        fades[0] = Letter.F;
        fades[1] = Letter.A;
        fades[2] = Letter.EMPTY;
        fades[3] = Letter.E;
        fades[4] = Letter.S;

        uint32[] memory fadesNegative = new uint32[](5);
        fadesNegative[4] = 6;

        bytes32[][] memory fadesBoundProofs = new bytes32[][](5);
        fadesBoundProofs[4] = m.getProof(words, 2);
        boardSystem.executeTyped{value: 1 ether}(
            fades,
            m.getProof(words, 3),
            Position(-2, 4),
            Direction.LEFT_TO_RIGHT,
            Bounds(new uint32[](5), fadesNegative, fadesBoundProofs)
        );

        Score memory fadesScore = scores.getValueAtAddress(deployer);
        // Counts for FADES and RAFTERS since two words made
        assertTrue(fadesScore.score == rafterScore.score + 10 + 9);
        assertTrue(fadesScore.rewards == 1 ether / 4);
        assertTrue(fadesScore.spent == 3 ether);

        // Claim the payout after the game
        vm.warp(block.timestamp + 1000000);
        uint256 prevBalance = address(deployer).balance;
        boardSystem.claimPayout();
        uint256 postBalance = address(deployer).balance;
        assertTrue(
            postBalance - prevBalance == 3 ether - 1 ether / 4 - 1 ether / 4
        );
    }

    function testCannotEarlyClaimPayout()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        // Play FITTED
        Letter[] memory fitted = new Letter[](6);
        fitted[0] = Letter.F;
        fitted[1] = Letter.EMPTY;
        fitted[2] = Letter.T;
        fitted[3] = Letter.T;
        fitted[4] = Letter.E;
        fitted[5] = Letter.D;

        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        boardSystem.executeTyped{value: 1 ether}(
            fitted,
            m.getProof(words, 0),
            Position(0, -1),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](6), new uint32[](6), new bytes32[][](6))
        );

        vm.expectRevert(GameNotOver.selector);
        boardSystem.claimPayout();
    }

    function testCannotDoubleClaimPayout()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        // Play FITTED
        Letter[] memory fitted = new Letter[](6);
        fitted[0] = Letter.F;
        fitted[1] = Letter.EMPTY;
        fitted[2] = Letter.T;
        fitted[3] = Letter.T;
        fitted[4] = Letter.E;
        fitted[5] = Letter.D;

        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        boardSystem.executeTyped{value: 1 ether}(
            fitted,
            m.getProof(words, 0),
            Position(0, -1),
            Direction.TOP_TO_BOTTOM,
            Bounds(new uint32[](6), new uint32[](6), new bytes32[][](6))
        );

        vm.warp(block.timestamp + 1000000);
        uint256 prevBalance = address(deployer).balance;
        boardSystem.claimPayout();
        uint256 postBalance = address(deployer).balance;
        assertTrue(postBalance - prevBalance == 1 ether - 1 ether / 4);

        vm.expectRevert(AlreadyClaimedPayout.selector);
        boardSystem.claimPayout();
    }
}
