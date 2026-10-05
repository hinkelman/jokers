defmodule JokersWeb.BoardComponentsTest do
  use ExUnit.Case, async: true

  alias Jokers.Board
  alias JokersWeb.BoardComponents

  defp last_move(before, steps) do
    {:ok, after_move} =
      Enum.reduce(steps, {:ok, before}, fn step, {:ok, board} -> Board.apply_step(board, step) end)

    %{steps: steps, before: before, after: after_move}
  end

  test "describing a split move that hits other marbles" do
    board = Board.new(4)

    before =
      board
      |> Board.place({:red, 0}, Board.track(board, :red, 10))
      |> Board.place({:red, 1}, Board.track(board, :red, 0))
      # an opponent's marble 5 ahead of red 1, and a teammate's 2 ahead of red 2
      |> Board.place({:black, 0}, Board.track(board, :red, 15))
      |> Board.place({:yellow, 3}, Board.track(board, :red, 2))

    move = last_move(before, [{:forward, {:red, 0}, 5}, {:forward, {:red, 1}, 2}])

    assert BoardComponents.describe_last_move(move) ==
             "red 1 moved 5 forward, from 2 spots past red's barn door to 6 spots before black's home door. " <>
               "It hit black 1, which went back to the barn. " <>
               "red 2 moved 2 forward, from 3 spots before red's home door to 1 spot before red's home door. " <>
               "It hit yellow 4, which went to its home door."

    assert [%{marble: {:red, 0}, from: {:track, 10}}, %{marble: {:red, 1}, from: {:track, 0}}] =
             BoardComponents.last_move_parts(move)
  end

  test "describing moves into the house and out of the barn" do
    board = Board.new(4) |> Board.place({:red, 4}, Board.track(Board.new(4), :red, 5))

    assert BoardComponents.describe_last_move(last_move(board, [{:backward, {:red, 4}, 8}])) ==
             "red 5 moved 8 back, from 2 spots past red's home door to 6 spots before red's home door."

    board = Board.place(board, {:red, 4}, Board.home_door(board, :red))

    assert BoardComponents.describe_last_move(last_move(board, [{:forward, {:red, 4}, 2}])) ==
             "red 5 moved 2 forward, from red's home door to red's house slot 2."

    assert BoardComponents.describe_last_move(last_move(board, [{:come_out, :red}])) ==
             "red 1 came out onto red's barn door."
  end

  test "describing a discard" do
    board = Board.new(4)

    assert BoardComponents.describe_last_move(%{steps: nil, before: board, after: board}) ==
             "You discarded."

    {:ok, after_move} = Board.come_out(board, :red)

    assert BoardComponents.describe_last_move(%{steps: nil, before: board, after: after_move}) ==
             "You discarded, and as it was your 5th discard in a row, " <>
               "red 1 came out onto red's barn door."
  end
end
