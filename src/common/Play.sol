// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import { Letter } from "./Letter.sol";

struct Position {
  int32 x;
  int32 y;
}

// Boundaries for a played word
struct Bounds {
  uint32[] positive; // Distance in the positive direction
  uint32[] negative; // Distance in the negative direction
  bytes32[][] proofs;
}

enum Direction {
  LEFT_TO_RIGHT,
  TOP_TO_BOTTOM
}
