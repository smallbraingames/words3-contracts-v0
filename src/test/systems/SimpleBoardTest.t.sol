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
import {Direction, Bounds} from "../../common/Play.sol";
import {Merkle} from "../murky/src/Merkle.sol";
import {console} from "forge-std/console.sol";
import "../../common/Errors.sol";

contract SimpleBoardTest is MudTest {
    bytes32[] public words;
    Merkle private m; // Store here to avoid stack too deep errors

    modifier setupBoard(address deployer) {
        vm.deal(deployer, 2 ether);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));
        boardSystem.setMerkleRoot(m.getRoot(words));
        boardSystem.setupInitialGrid();
        _;
    }

    function setUp() public override {
        super.setUp();
        m = new Merkle();
        words.push(keccak256(abi.encodePacked([Letter.H, Letter.I]))); // hi
        words.push(
            keccak256(
                abi.encodePacked(
                    [Letter.H, Letter.E, Letter.L, Letter.L, Letter.O]
                )
            )
        ); // hello
        words.push(
            keccak256(
                abi.encodePacked([Letter.W, Letter.O, Letter.R, Letter.D])
            )
        ); // word
        words.push(
            keccak256(
                abi.encodePacked([Letter.R, Letter.O, Letter.A, Letter.D])
            )
        ); // road
    }

    function testSetup() public prank(deployer) setupBoard(deployer) {
        vm.deal(deployer, 2 ether);

        TileComponent tiles = TileComponent(component(TileComponentID));
        assertTrue(tiles.hasTileAtPosition(Position({x: 0, y: 0})));
        assertTrue(!tiles.hasTileAtPosition(Position({x: -1, y: 0})));
        assertTrue(!tiles.hasTileAtPosition(Position({x: -1, y: -1})));
        assertTrue(tiles.hasTileAtPosition(Position({x: 6, y: 0})));
        Tile memory tile = tiles.getValueAtPosition(Position({x: 3, y: 0}));
        assertTrue(tile.letter == Letter.I);
    }

    function testPlayTwoWords() public prank(deployer) setupBoard(deployer) {
        vm.warp(block.timestamp + 300);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        playHello(boardSystem, 7, -1); // Play HELLO
        playHi(boardSystem, 7, -1); // Create HI, using the H from HELLO

        // Verify Tile Component
        TileComponent tiles = TileComponent(component(TileComponentID));
        assertTrue(tiles.hasTileAtPosition(Position({x: 7, y: -1})));
        Tile memory secondTile = tiles.getValueAtPosition(
            Position({x: 7, y: 1})
        );
        assertTrue(secondTile.letter == Letter.L);
        assertTrue(tiles.hasTileAtPosition(Position({x: 8, y: -1})));
        Tile memory rightTile = tiles.getValueAtPosition(
            Position({x: 8, y: -1})
        );
        assertTrue(rightTile.letter == Letter.I);
        assertTrue(!tiles.hasTileAtPosition(Position({x: 8, y: -2})));

        // Verify Score Component
        ScoreComponent scores = ScoreComponent(component(ScoreComponentID));
        Score memory score = scores.getValueAtAddress(deployer);
        assertTrue(score.spent == 2 ether);
        assertTrue(score.rewards == (uint256(1 ether) * 1) / 4);
        assertTrue(score.score == 13);

        // Verify Letter Count Component
        LetterCountComponent letterCount = LetterCountComponent(
            component(LetterCountComponentID)
        );
        assertTrue(letterCount.getValueAtLetter(Letter.H) == 1);
        assertTrue(letterCount.getValueAtLetter(Letter.E) == 0);
        assertTrue(letterCount.getValueAtLetter(Letter.L) == 2);
        assertTrue(letterCount.getValueAtLetter(Letter.O) == 1);
        assertTrue(letterCount.getValueAtLetter(Letter.I) == 1);

        // Verify treasury
        assertTrue(
            boardSystem.getTreasury() ==
                (uint256(1 ether) * 3) / 4 + (uint256(1 ether) * 3) / 4
        );
    }

    function testCannotPlayOverWord()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        vm.deal(deployer, 2 ether);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        playHello(boardSystem, 7, -1);

        // Play Hello on top of it but a couple letters down
        Letter[] memory word = new Letter[](5);
        word[0] = Letter.H;
        word[1] = Letter.E;
        word[2] = Letter.L;
        word[3] = Letter.L;
        word[4] = Letter.O;

        uint32[] memory negative = new uint32[](5);
        uint32[] memory positive = new uint32[](5);

        bytes32[] memory proof = m.getProof(words, 1);
        bytes32[][] memory proofs = new bytes32[][](5);
        vm.expectRevert(InvalidWordStart.selector);
        boardSystem.executeTyped{value: 1 ether}(
            word,
            proof,
            Position(7, 2),
            Direction.TOP_TO_BOTTOM,
            Bounds(positive, negative, proofs)
        );

        vm.expectRevert(InvalidWordEnd.selector);
        boardSystem.executeTyped{value: 1 ether}(
            word,
            proof,
            Position(7, -2),
            Direction.TOP_TO_BOTTOM,
            Bounds(positive, negative, proofs)
        );
    }

    function testCannotPlayEmptyWord()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        vm.deal(deployer, 2 ether);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));

        playHello(boardSystem, 7, -1);
        // Play the word hello over it with empty letters
        Letter[] memory word = new Letter[](5);
        word[0] = Letter.EMPTY;
        word[1] = Letter.EMPTY;
        word[2] = Letter.EMPTY;
        word[3] = Letter.EMPTY;
        word[4] = Letter.EMPTY;

        uint32[] memory negative = new uint32[](5);
        uint32[] memory positive = new uint32[](5);

        bytes32[] memory proof = m.getProof(words, 0);
        bytes32[][] memory proofs = new bytes32[][](5);

        vm.expectRevert(NoLettersPlayed.selector);
        boardSystem.executeTyped{value: 1 ether}(
            word,
            proof,
            Position(7, -1),
            Direction.TOP_TO_BOTTOM,
            Bounds(positive, negative, proofs)
        );
    }

    function testCannotImmediatelyClaimRewards()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        vm.deal(deployer, 2 ether);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));
        playHello(boardSystem, 7, -1);
        vm.expectRevert(GameNotOver.selector);
        boardSystem.claimPayout();
    }

    function testCannotPlayWordsNotConnect()
        public
        prank(deployer)
        setupBoard(deployer)
    {
        vm.deal(deployer, 2 ether);
        BoardSystem boardSystem = BoardSystem(system(BoardSystemID));
        playHello(boardSystem, 7, -1);
        // Play the word hi without connecting
        Letter[] memory word = new Letter[](2);
        word[0] = Letter.H;
        word[1] = Letter.I;

        uint32[] memory negative = new uint32[](2);
        uint32[] memory positive = new uint32[](2);

        bytes32[] memory proof = m.getProof(words, 0);
        bytes32[][] memory proofs = new bytes32[][](2);

        vm.expectRevert(LonelyWord.selector);
        boardSystem.executeTyped{value: 1 ether}(
            word,
            proof,
            Position(10, 1),
            Direction.LEFT_TO_RIGHT,
            Bounds(positive, negative, proofs)
        );
    }

    function playHello(
        BoardSystem boardSystem,
        int32 x,
        int32 y
    ) public {
        // Play hello
        Letter[] memory word = new Letter[](5);
        word[0] = Letter.H;
        word[1] = Letter.EMPTY;
        word[2] = Letter.L;
        word[3] = Letter.L;
        word[4] = Letter.O;

        uint32[] memory negative = new uint32[](5);
        uint32[] memory positive = new uint32[](5);

        bytes32[] memory proof = m.getProof(words, 1);
        bytes32[][] memory proofs = new bytes32[][](5);

        boardSystem.executeTyped{value: 1 ether}(
            word,
            proof,
            Position(x, y),
            Direction.TOP_TO_BOTTOM,
            Bounds(positive, negative, proofs)
        );
    }

    function playHi(
        BoardSystem boardSystem,
        int32 x,
        int32 y
    ) public {
        // Play the letter I on the existing H to make a HI
        Letter[] memory word = new Letter[](2);
        word[0] = Letter.EMPTY;
        word[1] = Letter.I;

        uint32[] memory negative = new uint32[](2);
        uint32[] memory positive = new uint32[](2);

        bytes32[] memory proof = m.getProof(words, 0);
        bytes32[][] memory proofs = new bytes32[][](2);

        boardSystem.executeTyped{value: 1 ether}(
            word,
            proof,
            Position(x, y),
            Direction.LEFT_TO_RIGHT,
            Bounds(positive, negative, proofs)
        );
    }
}
