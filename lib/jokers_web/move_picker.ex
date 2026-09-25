defmodule JokersWeb.MovePicker do
  @moduledoc """
  Choosing a move by clicking marbles on the board.

  Each move has a list of *targets*: the marbles a player clicks, in order, to choose it. These
  are the marbles it moves, plus the marble a joker lands on or the teammate's marble on the
  barn door. A marble in a barn is the target `{:barn, color}`, meaning "any marble from this
  barn", because it doesn't matter which one comes out.
  """

  alias Jokers.Board

  @type target :: Board.marble() | {:barn, Board.color()}

  @doc "The target a clicked marble stands for."
  @spec target(Board.t(), Board.marble()) :: target()
  def target(board, {color, _} = marble) do
    if Board.position(board, marble) == :barn, do: {:barn, color}, else: marble
  end

  @doc "The targets to click, in order, to choose a move."
  @spec targets(Board.t(), list(Board.step())) :: list(target())
  def targets(board, steps), do: Enum.flat_map(steps, &step_targets(board, &1))

  defp step_targets(_board, {direction, marble, _n}) when direction in [:forward, :backward],
    do: [marble]

  defp step_targets(_board, {:come_out, color}), do: [{:barn, color}]
  defp step_targets(board, {:joker, marble, target}), do: [marble, marble_at(board, target)]

  defp step_targets(board, {:joker_teammate, color, teammate}),
    do: [{:barn, color}, marble_at(board, Board.barn_door(board, teammate))]

  @doc "The marble at a position, or nil."
  @spec marble_at(Board.t(), Board.position()) :: Board.marble() | nil
  def marble_at(board, position) do
    Enum.find_value(board.marbles, fn {color, positions} ->
      idx = Enum.find_index(positions, &(&1 == position))
      idx && {color, idx}
    end)
  end

  @doc """
  The indexes (into `moves`) of the moves that start with the clicked marbles, in click order.
  """
  @spec matching(Board.t(), list({list(Board.step()), Board.t()}), list(Board.marble())) ::
          list(non_neg_integer())
  def matching(board, moves, picked) do
    picked = Enum.map(picked, &target(board, &1))

    for {{steps, _new_board}, index} <- Enum.with_index(moves),
        Enum.take(targets(board, steps), length(picked)) == picked,
        do: index
  end

  @doc "The marbles that can be clicked next."
  @spec clickable(Board.t(), list({list(Board.step()), Board.t()}), list(Board.marble())) ::
          list(Board.marble())
  def clickable(board, moves, picked) do
    board
    |> matching(moves, picked)
    |> Enum.flat_map(fn index ->
      {steps, _new_board} = Enum.at(moves, index)
      board |> targets(steps) |> Enum.drop(length(picked)) |> Enum.take(1)
    end)
    |> Enum.uniq()
    |> Enum.flat_map(&marbles(board, &1))
  end

  defp marbles(board, {:barn, color}) do
    for {:barn, idx} <- Enum.with_index(board.marbles[color]), do: {color, idx}
  end

  defp marbles(_board, marble), do: [marble]
end
