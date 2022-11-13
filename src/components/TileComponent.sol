// SPDX-License-Identifier: Unlicensed
// Adapted from Mud's CoordComponent (https://github.com/latticexyz/mud/blob/main/packages/std-contracts/src/components/CoordComponent.sol)
pragma solidity >=0.8.0;
import "solecs/BareComponent.sol";
import { Letter } from "../common/Letter.sol";
import { Tile } from "../common/Tile.sol";
import { Position } from "../common/Play.sol";

uint256 constant ID = uint256(keccak256("component.Tile"));

contract TileComponent is BareComponent {
  constructor(address world) BareComponent(world, ID) {}

  function getSchema() public pure override returns (string[] memory keys, LibTypes.SchemaValue[] memory values) {
    keys = new string[](1);
    values = new LibTypes.SchemaValue[](1);

    keys[0] = "value";
    values[0] = LibTypes.SchemaValue.UINT256;
  }

  function set(Tile calldata tile) public {
    set(
      getEntityAtPosition(tile.position),
      abi.encode(
        bytes32(
          bytes.concat(
            bytes20(tile.player),
            bytes4(uint32(tile.position.x)),
            bytes4(uint32(tile.position.y)),
            bytes1(uint8(tile.letter))
          )
        )
      )
    );
  }

  function getValue(uint256 entity) public view returns (Tile memory) {
    uint256 rawData = abi.decode(getRawValue(entity), (uint256));
    address player = address(uint160(rawData >> ((32 - 20) * 8)));
    int32 x = int32(uint32(((rawData << (20 * 8)) >> ((32 - 4) * 8))));
    int32 y = int32(uint32((rawData << (24 * 8)) >> ((32 - 4) * 8)));
    Letter letter = Letter(uint8((uint256(rawData) << (28 * 8)) >> ((32 - 1) * 8)));

    return Tile(player, Position({ x: x, y: y }), letter);
  }

  function hasTileAtPosition(Position memory position) public view returns (bool) {
    return has(getEntityAtPosition(position));
  }

  function getEntityAtPosition(Position memory position) public pure returns (uint256) {
    return uint256(keccak256(abi.encode(ID, position.x, position.y)));
  }

  function getValueAtPosition(Position memory position) public view returns (Tile memory) {
    return getValue(getEntityAtPosition(position));
  }
}
