# Jokers — Rules

## Setup

- **Players:** 4 or 6, in two teams (2 v 2 or 3 v 3). Teammates sit in alternating seats.
- **Cards:** three standard decks with two jokers each (162 cards). Each player is dealt 6 cards.
- **Marbles:** each player has 5 marbles of their color. They start in that player's **barn**.
- **Dealer:** the player to the left of the dealer goes first, and turns go clockwise.
  When a new game is played, the player on the dealer's left becomes the next dealer.

## Board

- Each player has one side of the board (square for 4 players, hexagon for 6).
- Each side has 18 track positions numbered 0–17, starting with the corner on the right.
- **Forward** is clockwise and **backward** is counterclockwise.
- **Barn door** = position 8 on your side. This is where your marbles enter the track.
- **Home door** = position 3 on your side. This is the last track position before your house.
  One step forward from the home door goes into house slot 1.
- Each **house** has 5 slots.

## Turns

1. Play one card from your hand and make its move.
2. Draw one card. When the draw pile is empty, shuffle the discard pile to make a new draw pile.

- If you have any legal move, you **must** play one.
- If you have no legal move, discard one card face up (and draw).
- **Five discards in a row:** the 5th consecutive discard brings one of your marbles out of the barn,
  if you still have marbles in the barn and your barn door is free. The count resets when you
  use it, and also when you bring a marble out with a card.
- Hands are secret, and there is no table talk.

## Cards

| Card  | Moves        | Can bring a marble out | Split    | Direction          |
|-------|--------------|------------------------|----------|--------------------|
| 2–6   | face value   | No                     | No       | Forward            |
| 7     | 7 total      | No                     | Optional | Forward            |
| 8     | 8            | No                     | No       | Backward           |
| 9     | 9 total      | No                     | Required | Forward + backward |
| 10    | 10           | No                     | No       | Forward            |
| J/Q/K | 10           | Yes                    | No       | Forward            |
| A     | 1 or 11      | Yes                    | No       | Forward            |
| Joker | special      | Yes                    | No       | Forward            |

### Coming out (J, Q, K, A, Joker)

- Move a marble from your barn onto your barn door.
- You can't come out if one of your own marbles is already on your barn door.
  The only exception is the joker's teammate move (see Joker).
- If an opponent's marble is on your barn door, it is hit (see Hitting).

### 7

- Move one marble 7 forward, **or** split the 7 between exactly two of your marbles.
- The player chooses which of the two parts is played first.
- If your last marble fills your last house slot, you play the rest of the 7 on a teammate's marble.
- Every part of a split must be used. If it can't be, the split isn't allowed.

### 9

- Must be split: one marble moves forward and a **different** marble moves backward.
  The two parts can be any sizes that add up to 9 (1 + 8 through 8 + 1).
- The player chooses which part is played first.
- A marble already in the house may take the forward part (moving deeper), but never the backward part.
- A 9 can't bring a marble out of the barn.
- If the forward part moves your last marble into your last house slot, the backward part is
  played on one of your teammate's marbles.
- Every part of a split must be used. If it can't be, the 9 can't be played.

### 8

- Move one track marble 8 backward. This works from any track position, including the barn door.
- Moving backward past your home door is a key strategy: come out, back up with an 8,
  then use small cards to get into the house.

### Joker

A joker can be used in one of three ways:

1. **Move onto a marble:** move one of your track marbles forward directly onto any opponent's
   or teammate's marble on the track, which is then hit. It can't move past your own home door
   or pass any of your own marbles.
2. **Teammate's barn door:** move a marble from your barn onto a teammate's barn door when the
   teammate has a marble there. The teammate's marble goes to their home door.
3. **Come out:** move a marble from your barn onto your own barn door, if you don't already
   have a marble there. This is usually a poor use of a joker.

A joker can't be used to move a marble from your barn onto an opponent's marble.

## Moving

- A marble can pass any marble that isn't its own color. It can't pass or land on its own color.
- Moves into the house are always forward and need the exact count.
- A marble can't go past its own home door. It must enter the house.
- Inside the house, a marble can move deeper but can't jump over other marbles.
- Marbles in the house can't move backward.

## Hitting

A marble is hit only when another marble **lands** on it. Passing it doesn't count, even during a split.

- **Opponent's marble:** goes back to its barn.
- **Teammate's marble:** goes to that teammate's home door.
  - If an opponent's marble is on that home door, it goes back to its barn.
  - If the teammate already has a marble on that home door, that marble goes back to their barn.
    (For now the code sends *any* marble on that home door back to its barn, including another
    teammate's marble or the hitting player's own marble. Revisit after some trial games.)
  - A teammate's marble that is hit while sitting on its own home door goes back to its barn.
- Marbles in the house are safe. Every track position can be hit, including a barn door.

## Helping teammates and winning

- Once all your marbles are in your house, you play your cards on the marbles of your teammate
  to the left, and then on the next teammate once that one is finished (in a 6-player game).
- When helping, you may bring a teammate's marbles out of their barn with J, Q, K, A or Joker.
- You can't move a teammate's marbles before all of yours are home, except for the rest of a 7
  or the backward part of a 9 when your last marble goes into your last house slot.
- A team wins when all of its players' marbles are in their houses.
