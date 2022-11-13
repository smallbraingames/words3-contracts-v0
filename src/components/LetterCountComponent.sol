// SPDX-License-Identifier: Unlicense
// Adapted from UInt256 Component (cannot use default UInt256 Component since this must be bare)
pragma solidity >=0.8.0;
import { Letter } from "../common/Letter.sol";
import "std-contracts/components/UInt32BareComponent.sol";
import { console } from "forge-std/console.sol";


uint256 constant ID = uint256(keccak256("component.LetterCount"));

contract LetterCountComponent is Uint32BareComponent {
  constructor(address world) Uint32BareComponent(world, ID) {}

  function getEntityAtLetter(Letter letter) private pure returns (uint256) {
    return uint256(keccak256(abi.encode(ID, uint8(letter))));
  }

  function getValueAtLetter(Letter letter) public view returns (uint32) {
    uint256 entity = getEntityAtLetter(letter);
    if (!has(entity)) return 0;
    return getValue(entity);
  }

  function incrementValueAtLetter(Letter letter) public {
    uint256 entity = getEntityAtLetter(letter);
    uint256 letterCount = getValueAtLetter(letter);
    set(entity, abi.encode(letterCount + 1));
  }
}
