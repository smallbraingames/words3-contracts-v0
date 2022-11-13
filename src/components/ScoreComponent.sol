// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0;
import "solecs/BareComponent.sol";
import { addressToEntity } from "solecs/utils.sol";
import { Score } from "../common/Score.sol";

uint256 constant ID = uint256(keccak256("component.Score"));

contract ScoreComponent is BareComponent {
  uint32 private totalScore;

  constructor(address world) BareComponent(world, ID) {}

  function getSchema() public pure override returns (string[] memory keys, LibTypes.SchemaValue[] memory values) {
    keys = new string[](3);
    values = new LibTypes.SchemaValue[](3);

    keys[0] = "spent";
    values[0] = LibTypes.SchemaValue.UINT256;

    keys[1] = "rewards";
    values[1] = LibTypes.SchemaValue.UINT256;

    keys[2] = "score";
    values[2] = LibTypes.SchemaValue.UINT32;
  }

  function set(
    address player,
    uint256 spent,
    uint256 rewards,
    uint32 score
  ) public {
    set(getEntityAtAddress(player), abi.encode(Score({ spent: spent, rewards: rewards, score: score })));
  }

  function getValue(uint256 entity) public view returns (Score memory) {
    Score memory score = abi.decode(getRawValue(entity), (Score));
    return score;
  }

  function getEntityAtAddress(address player) public pure returns (uint256) {
    return addressToEntity(player);
  }

  function getValueAtAddress(address player) public view returns (Score memory) {
    uint256 entity = getEntityAtAddress(player);
    return getValue(entity);
  }

  function hasValueAtAddress(address player) public view returns (bool) {
    return has(getEntityAtAddress(player));
  }

  function incrementValueAtAddress(
    address player,
    uint256 spent,
    uint256 rewards,
    uint32 score
  ) public {
    if (hasValueAtAddress(player)) {
      Score memory previous = getValueAtAddress(player);
      set(player, previous.spent + spent, previous.rewards + rewards, previous.score + score);
    } else {
      set(player, spent, rewards, score);
    }
    totalScore += score;
  }

  function getTotalScore() public view returns (uint32) {
    return totalScore;
  }
}
