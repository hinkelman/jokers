defmodule JokersWeb.MovePickerTest do
  use ExUnit.Case, async: true

  alias Jokers.Board
  alias JokersWeb.MovePicker

  setup do
    board = Board.new(4)
    %{board: board}
  end

  test "any barn marble picks coming out", %{board: board} do
    moves = Board.legal_moves(board, :red, {:hearts, :queen})
    assert MovePicker.clickable(board, moves, []) == for(i <- 0..4, do: {:red, i})
    assert MovePicker.matching(board, moves, [{:red, 3}]) == [0]
  end

  test "a split is picked one marble at a time", %{board: board} do
    board =
      board
      |> Board.place({:red, 0}, Board.track(board, :red, 8))
      |> Board.place({:red, 1}, Board.track(board, :black, 0))

    moves = Board.legal_moves(board, :red, {:clubs, 7})
    assert Enum.sort(MovePicker.clickable(board, moves, [])) == [{:red, 0}, {:red, 1}]

    # red 1 alone, or red 1 then red 2
    assert MovePicker.clickable(board, moves, [{:red, 0}]) == [{:red, 1}]
    first = MovePicker.matching(board, moves, [{:red, 0}])
    both = MovePicker.matching(board, moves, [{:red, 0}, {:red, 1}])
    assert length(first) == length(both) + 1
    assert Enum.all?(both, &(&1 in first))
  end

  test "a joker picks its marble, then the marble it lands on", %{board: board} do
    board =
      board
      |> Board.place({:red, 0}, Board.track(board, :red, 8))
      |> Board.place({:black, 0}, Board.track(board, :red, 12))

    moves = Board.legal_moves(board, :red, {:red, :joker})
    assert {:red, 0} in MovePicker.clickable(board, moves, [])
    assert MovePicker.clickable(board, moves, [{:red, 0}]) == [{:black, 0}]
    assert [_only] = MovePicker.matching(board, moves, [{:red, 0}, {:black, 0}])
  end
end
