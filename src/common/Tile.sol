// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import { Letter } from "./Letter.sol";
import { Position } from "./Play.sol";

struct Tile {
  address player;
  Position position;
  Letter letter;
}
