defmodule Jokers.BoardTest do
  use ExUnit.Case, async: true

  alias Jokers.Board

  # 4-player seats, clockwise: red, black, yellow, blue (red + yellow vs black + blue)
  setup do
    %{board: Board.new(4)}
  end

  defp at(board, color, pos), do: Board.track(board, color, pos)

  defp place_all(board, placements) do
    Enum.reduce(placements, board, fn {marble, pos}, acc -> Board.place(acc, marble, pos) end)
  end

  test "seats and teams" do
    board4 = Board.new(4)
    assert board4.seats == [:red, :black, :yellow, :blue]
    assert Enum.all?(board4.marbles[:red], &(&1 == :barn))
    assert Board.teammates?(board4, :red, :yellow)
    refute Board.teammates?(board4, :red, :black)
    assert Board.teammates(board4, :black) == [:blue]

    board6 = Board.new(6)
    assert board6.seats == [:red, :black, :yellow, :blue, :white, :green]
    assert Board.teammates(board6, :black) == [:blue, :green]
  end

  test "track positions", %{board: board} do
    assert Board.side_position(board, at(board, :yellow, 8)) == {:yellow, 8}
    assert Board.track_length(board) == 72
  end

  test "moving forward continues onto the side on the left", %{board: board} do
    board = Board.place(board, {:red, 0}, at(board, :red, 15))
    {:ok, board} = Board.move(board, {:red, 0}, 4, :forward)
    assert Board.position(board, {:red, 0}) == at(board, :black, 1)
  end

  test "coming out", %{board: board} do
    {:ok, board} = Board.come_out(board, :red)
    assert Board.position(board, {:red, 0}) == at(board, :red, 8)
    # can't come out onto your own marble
    assert Board.come_out(board, :red) == :error
  end

  test "coming out hits marbles on the barn door", %{board: board} do
    opponent = Board.place(board, {:black, 0}, at(board, :red, 8))
    {:ok, opponent} = Board.come_out(opponent, :red)
    assert Board.position(opponent, {:black, 0}) == :barn

    teammate = Board.place(board, {:yellow, 0}, at(board, :red, 8))
    {:ok, teammate} = Board.come_out(teammate, :red)
    assert Board.position(teammate, {:yellow, 0}) == at(board, :yellow, 3)
  end

  test "a teammate's marble already on its home door goes to the barn", %{board: board} do
    board =
      place_all(board, [{{:yellow, 0}, at(board, :red, 8)}, {{:yellow, 1}, at(board, :yellow, 3)}])

    {:ok, board} = Board.come_out(board, :red)
    assert Board.position(board, {:yellow, 0}) == at(board, :yellow, 3)
    assert Board.position(board, {:yellow, 1}) == :barn
  end

  test "entering the house needs the exact count", %{board: board} do
    door = Board.place(board, {:red, 0}, at(board, :red, 3))
    assert {:ok, b} = Board.move(door, {:red, 0}, 1, :forward)
    assert Board.position(b, {:red, 0}) == {:house, 1}
    assert {:ok, b} = Board.move(door, {:red, 0}, 5, :forward)
    assert Board.position(b, {:red, 0}) == {:house, 5}
    assert Board.move(door, {:red, 0}, 6, :forward) == :error
  end

  test "can't jump over marbles in the house", %{board: board} do
    board = place_all(board, [{{:red, 0}, at(board, :red, 1)}, {{:red, 1}, {:house, 2}}])
    assert {:ok, _} = Board.move(board, {:red, 0}, 3, :forward)
    assert Board.move(board, {:red, 0}, 4, :forward) == :error
    assert Board.move(board, {:red, 0}, 5, :forward) == :error
  end

  test "passing and landing", %{board: board} do
    board = Board.place(board, {:red, 0}, at(board, :red, 8))

    own = Board.place(board, {:red, 1}, at(board, :red, 10))
    assert Board.move(own, {:red, 0}, 3, :forward) == :error
    assert Board.move(own, {:red, 0}, 2, :forward) == :error

    other = Board.place(board, {:black, 0}, at(board, :red, 10))
    {:ok, passed} = Board.move(other, {:red, 0}, 3, :forward)
    assert Board.position(passed, {:black, 0}) == at(board, :red, 10)
    {:ok, landed} = Board.move(other, {:red, 0}, 2, :forward)
    assert Board.position(landed, {:black, 0}) == :barn
  end

  test "a teammate's marble hit on its own home door goes to the barn", %{board: board} do
    board =
      place_all(board, [{{:red, 0}, at(board, :yellow, 1)}, {{:yellow, 0}, at(board, :yellow, 3)}])

    {:ok, board} = Board.move(board, {:red, 0}, 2, :forward)
    assert Board.position(board, {:yellow, 0}) == :barn
  end

  test "backing up past the home door", %{board: board} do
    board = Board.place(board, {:red, 0}, at(board, :red, 8))
    {:ok, board} = Board.move(board, {:red, 0}, 8, :backward)
    assert Board.position(board, {:red, 0}) == at(board, :red, 0)
    {:ok, board} = Board.move(board, {:red, 0}, 4, :forward)
    assert Board.position(board, {:red, 0}) == {:house, 1}
    assert Board.move(board, {:red, 0}, 1, :backward) == :error
  end

  test "joker onto a marble can't pass the home door", %{board: board} do
    board = Board.place(board, {:red, 0}, at(board, :red, 0))
    beyond = Board.place(board, {:black, 0}, at(board, :red, 5))
    assert Board.joker(beyond, {:red, 0}, at(board, :red, 5)) == :error

    before = Board.place(board, {:black, 0}, at(board, :red, 2))
    {:ok, before} = Board.joker(before, {:red, 0}, at(board, :red, 2))
    assert Board.position(before, {:red, 0}) == at(board, :red, 2)
    assert Board.position(before, {:black, 0}) == :barn

    # can't pass your own marble
    blocked =
      place_all(board, [{{:red, 1}, at(board, :red, 1)}, {{:black, 0}, at(board, :red, 2)}])

    assert Board.joker(blocked, {:red, 0}, at(board, :red, 2)) == :error
  end

  test "joker onto a teammate's barn door", %{board: board} do
    board =
      place_all(board, [{{:yellow, 0}, at(board, :yellow, 8)}, {{:red, 0}, at(board, :red, 8)}])

    {:ok, board} = Board.joker_teammate(board, :red, :yellow)
    assert Board.position(board, {:red, 1}) == at(board, :yellow, 8)
    assert Board.position(board, {:yellow, 0}) == at(board, :yellow, 3)
    assert Board.joker_teammate(board, :red, :black) == :error
  end

  test "legal moves at the start of the game", %{board: board} do
    assert Board.legal_moves(board, :red, {:hearts, 5}) == []
    assert [{[{:come_out, :red}], _}] = Board.legal_moves(board, :red, {:hearts, :queen})
    assert [{[{:come_out, :red}], _}] = Board.legal_moves(board, :red, {:red, :joker})
  end

  test "a 7 that finishes your marbles is finished by a teammate", %{board: board} do
    board =
      place_all(board, [
        {{:red, 0}, {:house, 2}},
        {{:red, 1}, {:house, 3}},
        {{:red, 2}, {:house, 4}},
        {{:red, 3}, {:house, 5}},
        {{:red, 4}, at(board, :red, 1)},
        {{:yellow, 0}, at(board, :yellow, 8)}
      ])

    steps = [{:forward, {:red, 4}, 3}, {:forward, {:yellow, 0}, 4}]
    {:ok, played} = Board.play(board, :red, {:clubs, 7}, steps)
    assert Board.finished?(played, :red)
    assert Board.position(played, {:yellow, 0}) == at(board, :yellow, 12)

    # a whole 7 overshoots the house
    assert Board.play(board, :red, {:clubs, 7}, [{:forward, {:red, 4}, 7}]) ==
             {:error, :illegal_move}
  end

  test "every part of a split must be used", %{board: board} do
    # yellow is already home, so red's last marble can't use the rest of the 7
    board =
      board
      |> place_all(for i <- 0..4, do: {{:yellow, i}, {:house, i + 1}})
      |> place_all(for i <- 0..3, do: {{:red, i}, {:house, i + 2}})
      |> Board.place({:red, 4}, at(board, :red, 1))

    assert Board.legal_moves(board, :red, {:clubs, 7}) == []
    assert [_] = Board.legal_moves(board, :red, {:clubs, 3})
  end

  test "a 9 can move a marble deeper into the house", %{board: board} do
    board = place_all(board, [{{:red, 0}, {:house, 1}}, {{:red, 1}, at(board, :black, 0)}])
    steps = [{:forward, {:red, 0}, 4}, {:backward, {:red, 1}, 5}]
    {:ok, played} = Board.play(board, :red, {:spades, 9}, steps)
    assert Board.position(played, {:red, 0}) == {:house, 5}
    assert Board.position(played, {:red, 1}) == at(board, :red, 13)
  end

  test "a 9 needs one marble forward and another backward", %{board: board} do
    one = Board.place(board, {:red, 0}, at(board, :red, 8))
    assert Board.legal_moves(one, :red, {:spades, 9}) == []

    two = Board.place(one, {:red, 1}, at(board, :black, 0))
    moves = Board.legal_moves(two, :red, {:spades, 9})
    assert moves != []

    for {steps, _} <- moves do
      assert steps |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [:backward, :forward]
    end
  end

  test "a finished player moves their teammate's marbles", %{board: board} do
    board =
      board
      |> place_all(for i <- 0..4, do: {{:red, i}, {:house, i + 1}})
      |> Board.place({:yellow, 0}, at(board, :yellow, 8))

    assert Board.acting_color(board, :red) == :yellow
    assert [{[{:forward, {:yellow, 0}, 5}], _}] = Board.legal_moves(board, :red, {:hearts, 5})
  end
end
