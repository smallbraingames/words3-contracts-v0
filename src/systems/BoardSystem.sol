// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;
import "solecs/System.sol";
import {IWorld} from "solecs/interfaces/IWorld.sol";
import {getAddressById} from "solecs/utils.sol";
import {TileComponent, ID as TileComponentID} from "../components/TileComponent.sol";
import {ScoreComponent, ID as ScoreComponentID} from "../components/ScoreComponent.sol";
import {LetterCountComponent, ID as LetterCountComponentID} from "../components/LetterCountComponent.sol";
import {Letter} from "../common/Letter.sol";
import {Tile} from "../common/Tile.sol";
import {Score} from "../common/Score.sol";
import {Direction, Bounds, Position} from "../common/Play.sol";
import {LinearVRGDA} from "../vrgda/LinearVRGDA.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {LibBoard} from "../libraries/LibBoard.sol";
import "../common/Errors.sol";

uint256 constant ID = uint256(keccak256("system.Board"));

/// @title Game Board System for Words3
/// @author Small Brain Games
/// @notice Logic for placing words, scoring points, and claiming winnings
contract BoardSystem is System, LinearVRGDA {
    /// ============ Immutable Storage ============

    /// @notice Target price for a token, to be scaled according to sales pace.
    int256 public immutable vrgdaTargetPrice = 5e14;
    /// @notice The percent price decays per unit of time with no sales, scaled by 1e18.
    int256 public immutable vrgdaPriceDecayPercent = 0.85e18;
    /// @notice The number of tokens to target selling in 1 full unit of time, scaled by 1e18.
    int256 public immutable vrgdaPerTimeUnit = 20e18;
    /// @notice Start time for vrgda calculations
    uint256 public immutable startTime = block.timestamp;

    /// @notice End time for game end
    uint256 public immutable endTime = block.timestamp + 86400 * 7;
    /// @notice Amount of sales that go to rewards (1/4)
    uint256 public immutable rewardFraction = 4;

    /// @notice Merkle root for dictionary of words
    bytes32 private merkleRoot =
        0xd848d23e6ac07f7c22c9cb0e121f568619a636d37fab669e76595adfda216273;

    /// @notice Mapping for point values of letters, set up in setupLetterPoints()
    mapping(Letter => uint8) private letterValue;

    /// ============ Mutable Storage (ECS Sin, but gas savings) ============

    /// @notice Mapping to store if a player has claimed their end of game payout
    mapping(address => bool) private claimedPayout;
    /// @notice Store of treasury to be paid out to game winners
    uint256 private treasury;

    constructor(IWorld _world, address _components)
        LinearVRGDA(vrgdaTargetPrice, vrgdaPriceDecayPercent, vrgdaPerTimeUnit)
        System(_world, _components)
    {
        setupLetterPoints();
    }

    /// ============ Public functions ============

    // HERE FOR TESTING PURPOSES
    function setMerkleRoot(bytes32 newMerkleRoot) public {
        merkleRoot = newMerkleRoot;
    }

    function execute(bytes memory arguments) public returns (bytes memory) {
        (
            Letter[] memory word,
            bytes32[] memory proof,
            Position memory position,
            Direction direction,
            Bounds memory bounds
        ) = abi.decode(
                arguments,
                (Letter[], bytes32[], Position, Direction, Bounds)
            );
        executeInternal(word, proof, position, direction, bounds);
    }

    /// @notice Checks if a move is valid and if so, plays a word on the board.
    /// @param word The letters of the word being played, empty letters mean using existing letters on board.
    /// @param proof The Merkle proof that the word is in the dictionary.
    /// @param position The starting position that the word is being played from.
    /// @param direction The direction the word is being played (top-down, or left-to-right).
    /// @param bounds The bounds of all other words on the cross axis this word makes.
    function executeTyped(
        Letter[] memory word,
        bytes32[] memory proof,
        Position memory position,
        Direction direction,
        Bounds memory bounds
    ) public payable returns (bytes memory) {
        return execute(abi.encode(word, proof, position, direction, bounds));
    }

    /// @notice Claims winnings for a player at game end, can only be called once.
    function claimPayout() public {
        if (!isGameOver()) revert GameNotOver();
        if (claimedPayout[msg.sender]) revert AlreadyClaimedPayout();
        claimedPayout[msg.sender] = true;
        ScoreComponent scores = ScoreComponent(
            getAddressById(components, ScoreComponentID)
        );
        Score memory playerScore = scores.getValueAtAddress(msg.sender);
        uint256 winnings = (treasury * playerScore.score) /
            uint256(scores.getTotalScore());
        uint256 rewards = playerScore.rewards;
        payable(msg.sender).transfer(winnings + rewards);
    }

    /// @notice Allows anyone to seed the treasury for this game with extra funds.
    function fundTreasury() public payable {
        if (msg.value > 0) {
            treasury += msg.value;
        }
    }

    /// @notice Gets funds in treasury (only treasury, not player rewards).
    function getTreasury() public view returns (uint256) {
        return treasury;
    }

    /// @notice Plays the first word "infinite" on the board.
    function setupInitialGrid() public {
        TileComponent tiles = TileComponent(
            getAddressById(components, TileComponentID)
        );
        if (tiles.hasTileAtPosition(Position({x: 0, y: 0})))
            revert AlreadySetupGrid();
        tiles.set(Tile(address(0), Position({x: 0, y: 0}), Letter.I));
        tiles.set(Tile(address(0), Position({x: 1, y: 0}), Letter.N));
        tiles.set(Tile(address(0), Position({x: 2, y: 0}), Letter.F));
        tiles.set(Tile(address(0), Position({x: 3, y: 0}), Letter.I));
        tiles.set(Tile(address(0), Position({x: 4, y: 0}), Letter.N));
        tiles.set(Tile(address(0), Position({x: 5, y: 0}), Letter.I));
        tiles.set(Tile(address(0), Position({x: 6, y: 0}), Letter.T));
        tiles.set(Tile(address(0), Position({x: 7, y: 0}), Letter.E));
    }

    /// ============ Private functions ============

    /// @notice Internal function to check if a move is valid and if so, play it on the board.
    /// @dev Making execute payable breaks the System interface, so executeInternal is needed.
    function executeInternal(
        Letter[] memory word,
        bytes32[] memory proof,
        Position memory position,
        Direction direction,
        Bounds memory bounds
    ) private {
        // Ensure game is not ever
        if (isGameOver()) revert GameOver();

        // Ensure payment is sufficient
        uint256 price = getPriceForWord(word);
        if (msg.value < price) revert PaymentTooLow();

        // Increment letter counts
        LetterCountComponent letterCount = LetterCountComponent(
            getAddressById(components, LetterCountComponentID)
        );
        for (uint32 i = 0; i < word.length; i++) {
            if (word[i] != Letter.EMPTY) {
                letterCount.incrementValueAtLetter(word[i]);
            }
        }

        // Increment treasury
        treasury += (msg.value * (rewardFraction - 1)) / rewardFraction;

        // Check if move is valid, and if so, make it
        makeMoveChecked(word, proof, position, direction, bounds);
    }

    /// @notice Checks if a move is valid, and if so, update TileComponent and ScoreComponent.
    function makeMoveChecked(
        Letter[] memory word,
        bytes32[] memory proof,
        Position memory position,
        Direction direction,
        Bounds memory bounds
    ) private {
        TileComponent tiles = TileComponent(
            getAddressById(components, TileComponentID)
        );
        checkWord(word, proof, position, direction, tiles);
        checkBounds(word, position, direction, bounds, tiles);
        Letter[] memory filledWord = processWord(
            word,
            position,
            direction,
            tiles
        );
        countPointsChecked(filledWord, position, direction, bounds, tiles);
    }

    /// @notice Checks if a word is 1) played on another word, 2) has at least one letter, 3) is a valid word, 4) has valid bounds, and 5) has not been played yet
    function checkWord(
        Letter[] memory word,
        bytes32[] memory proof,
        Position memory position,
        Direction direction,
        TileComponent tiles
    ) public view {
        // Ensure word is less than 200 letters
        if (word.length > 200) revert WordTooLong();
        // Ensure word isn't missing letters at edges
        if (
            tiles.hasTileAtPosition(
                LibBoard.getLetterPosition(-1, position, direction)
            )
        ) revert InvalidWordStart();
        if (
            tiles.hasTileAtPosition(
                LibBoard.getLetterPosition(
                    int32(uint32(word.length)),
                    position,
                    direction
                )
            )
        ) revert InvalidWordEnd();

        bool emptyTile = false;
        bool nonEmptyTile = false;

        Letter[] memory filledWord = new Letter[](word.length);

        for (uint32 i = 0; i < word.length; i++) {
            Position memory letterPosition = LibBoard.getLetterPosition(
                int32(i),
                position,
                direction
            );
            if (word[i] == Letter.EMPTY) {
                emptyTile = true;

                // Ensure empty letter is played on existing letter
                if (!tiles.hasTileAtPosition(letterPosition))
                    revert EmptyLetterNotOnExisting();

                filledWord[i] = tiles.getValueAtPosition(letterPosition).letter;
            } else {
                nonEmptyTile = true;

                // Ensure non-empty letter is played on empty tile
                if (tiles.hasTileAtPosition(letterPosition))
                    revert LetterOnExistingTile();

                filledWord[i] = word[i];
            }
        }

        // Ensure word is played on another word
        if (!emptyTile) revert LonelyWord();
        // Ensure word has at least one letter
        if (!nonEmptyTile) revert NoLettersPlayed();
        // Ensure word is a valid word
        LibBoard.verifyWordProof(filledWord, proof, merkleRoot);
    }

    /// @notice Checks if the given bounds for other words on the cross axis are well formed.
    function checkBounds(
        Letter[] memory word,
        Position memory position,
        Direction direction,
        Bounds memory bounds,
        TileComponent tiles
    ) private view {
        // Ensure bounds of equal length
        if (bounds.positive.length != bounds.negative.length)
            revert BoundsDoNotMatch();
        // Ensure bounds of correct length
        if (bounds.positive.length != word.length) revert InvalidBoundLength();
        // Ensure proof of correct length
        if (bounds.positive.length != bounds.proofs.length)
            revert InvalidCrossProofs();

        // Ensure positive and negative bounds are valid
        for (uint32 i; i < word.length; i++) {
            if (word[i] == Letter.EMPTY) {
                // Ensure bounds are 0 if letter is empty
                // since you cannot get points for words formed by letters you did not play
                if (bounds.positive[i] != 0 || bounds.negative[i] != 0)
                    revert InvalidEmptyLetterBound();
            } else {
                // Ensure bounds are valid (empty at edges) for nonempty letters
                // Bounds that are too large will be caught while verifying formed words
                (Position memory start, Position memory end) = LibBoard
                    .getOutsideBoundPositions(
                        LibBoard.getLetterPosition(
                            int32(i),
                            position,
                            direction
                        ),
                        direction,
                        bounds.positive[i],
                        bounds.negative[i]
                    );
                if (
                    tiles.hasTileAtPosition(start) ||
                    tiles.hasTileAtPosition(end)
                ) revert InvalidBoundEdges();
            }
        }
    }

    /// @notice 1) Places the word on the board, 2) adds word rewards to other players, and 3) returns a filled in word.
    /// @return filledWord A word that has empty letters replaced with the underlying letters from the board.
    function processWord(
        Letter[] memory word,
        Position memory position,
        Direction direction,
        TileComponent tiles
    ) private returns (Letter[] memory) {
        Letter[] memory filledWord = new Letter[](word.length);

        // Rewards are tracked in the score component
        ScoreComponent scores = ScoreComponent(
            getAddressById(components, ScoreComponentID)
        );

        // Evenly split the reward fraction of among tiles the player used to create their word
        // Rewards are only awarded to players who are used in the "primary" word
        uint256 rewardPerEmptyTile = LibBoard.getRewardPerEmptyTile(
            word,
            rewardFraction,
            msg.value
        );

        // Place tiles and fill filledWord
        for (uint32 i = 0; i < word.length; i++) {
            Position memory letterPosition = LibBoard.getLetterPosition(
                int32(i),
                position,
                direction
            );
            if (word[i] == Letter.EMPTY) {
                Tile memory tile = tiles.getValueAtPosition(letterPosition);
                scores.incrementValueAtAddress(
                    tile.player,
                    0,
                    rewardPerEmptyTile,
                    0
                );
                filledWord[i] = tile.letter;
            } else {
                tiles.set(
                    Tile(
                        msg.sender,
                        Position({x: letterPosition.x, y: letterPosition.y}),
                        word[i]
                    )
                );
                filledWord[i] = word[i];
            }
        }
        return filledWord;
    }

    /// @notice Updates the score for a player for the main word and cross words and checks every cross word.
    /// @dev Expects a word input with empty letters filled in
    function countPointsChecked(
        Letter[] memory filledWord,
        Position memory position,
        Direction direction,
        Bounds memory bounds,
        TileComponent tiles
    ) private {
        uint32 points = countPointsForWord(filledWord);
        // Count points for perpendicular word
        // This double counts points on purpose (points are recounted for every valid word)
        for (uint32 i; i < filledWord.length; i++) {
            if (bounds.positive[i] != 0 || bounds.negative[i] != 0) {
                Letter[] memory perpendicularWord = LibBoard
                    .getWordInBoundsChecked(
                        LibBoard.getLetterPosition(
                            int32(i),
                            position,
                            direction
                        ),
                        direction,
                        bounds.positive[i],
                        bounds.negative[i],
                        tiles
                    );
                LibBoard.verifyWordProof(
                    perpendicularWord,
                    bounds.proofs[i],
                    merkleRoot
                );
                points += countPointsForWord(perpendicularWord);
            }
        }
        ScoreComponent scores = ScoreComponent(
            getAddressById(components, ScoreComponentID)
        );
        scores.incrementValueAtAddress(msg.sender, msg.value, 0, points);
    }

    /// @notice Ge the points for a given word. The points are simply a sum of the letter point values.
    function countPointsForWord(Letter[] memory word)
        private
        view
        returns (uint32)
    {
        uint32 points;
        for (uint32 i; i < word.length; i++) {
            points += letterValue[word[i]];
        }
        return points;
    }

    /// @notice Get price for a letter using a linear VRGDA.
    function getPriceForLetter(Letter letter) public view returns (uint256) {
        LetterCountComponent letterCount = LetterCountComponent(
            getAddressById(components, LetterCountComponentID)
        );
        return
            getVRGDAPrice(
                toDaysWadUnsafe(block.timestamp - startTime),
                ((letterValue[letter] + 1) / 2) *
                    letterCount.getValueAtLetter(letter)
            );
    }

    /// @notice Get price for a word using a linear VRGDA.
    function getPriceForWord(Letter[] memory word)
        public
        view
        returns (uint256)
    {
        uint256 price;
        for (uint256 i = 0; i < word.length; i++) {
            if (word[i] != Letter.EMPTY) {
                price += getPriceForLetter(word[i]);
            }
        }
        return price;
    }

    /// @notice Get if game is over.
    function isGameOver() private view returns (bool) {
        return block.timestamp >= endTime;
    }

    /// ============ Setup functions ============

    function setupLetterPoints() private {
        letterValue[Letter.A] = 1;
        letterValue[Letter.B] = 3;
        letterValue[Letter.C] = 3;
        letterValue[Letter.D] = 2;
        letterValue[Letter.E] = 1;
        letterValue[Letter.F] = 4;
        letterValue[Letter.G] = 2;
        letterValue[Letter.H] = 4;
        letterValue[Letter.I] = 1;
        letterValue[Letter.J] = 8;
        letterValue[Letter.K] = 5;
        letterValue[Letter.L] = 1;
        letterValue[Letter.M] = 3;
        letterValue[Letter.N] = 1;
        letterValue[Letter.O] = 1;
        letterValue[Letter.P] = 3;
        letterValue[Letter.Q] = 10;
        letterValue[Letter.R] = 1;
        letterValue[Letter.S] = 1;
        letterValue[Letter.T] = 1;
        letterValue[Letter.U] = 1;
        letterValue[Letter.V] = 4;
        letterValue[Letter.W] = 4;
        letterValue[Letter.X] = 8;
        letterValue[Letter.Y] = 4;
        letterValue[Letter.Z] = 10;
    }
}
