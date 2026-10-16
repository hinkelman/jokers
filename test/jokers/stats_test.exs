defmodule Jokers.StatsTest do
  use ExUnit.Case, async: true

  alias Jokers.{Board, Stats}

  test "each team's strong cards, knockouts and discards" do
    start = Board.new(4)
    spot = Board.track(start, :black, 4)
    black_out = Board.place(start, {:black, 0}, spot)
    # red's joker lands on black's marble, which goes back to the barn
    red_on = Board.place(start, {:red, 0}, spot)
    yellow_out = Board.place(red_on, {:yellow, 0}, Board.barn_door(start, :yellow))

    history = [
      %{player: :black, card: {:spades, :king}, discard: false, before: start, after: black_out},
      %{player: :red, card: {:red, :joker}, discard: false, before: black_out, after: red_on},
      %{player: :blue, card: {:hearts, 9}, discard: true, before: red_on, after: red_on},
      %{player: :yellow, card: {:clubs, :ace}, discard: false, before: red_on, after: yellow_out},
      %{player: :red, card: {:clubs, 8}, discard: false, before: yellow_out, after: yellow_out},
      %{player: :black, card: {:clubs, 9}, discard: false, before: yellow_out, after: yellow_out},
      %{player: :blue, card: {:clubs, 5}, discard: false, before: yellow_out, after: yellow_out}
    ]

    assert Stats.teams(start, history) == [
             %{jokers: 1, aces: 1, faces: 0, eights: 1, nines: 0, knockouts: 1, discards: 0},
             # the discarded 9 doesn't count as played
             %{jokers: 0, aces: 0, faces: 1, eights: 0, nines: 1, knockouts: 0, discards: 1}
           ]
  end
end
