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
  defp step_targets(board, {:joker, marble, target}), do: [marble, Board.marble_at(board, target)]

  defp step_targets(board, {:joker_teammate, color, teammate}),
    do: [{:barn, color}, Board.marble_at(board, Board.barn_door(board, teammate))]

  @doc """
  Sorts moves for the list shown to the player: by the number of the first marble moved, then
  backward moves before forward moves, then by distance, and the same again for the second part
  of a split. Moves that bring a marble out of the barn come first.
  """
  @spec sort(list({list(Board.step()), Board.t()})) :: list({list(Board.step()), Board.t()})
  def sort(moves) do
    Enum.sort_by(moves, fn {steps, _new_board} -> Enum.map(steps, &sort_key/1) end)
  end

  defp sort_key({:come_out, _color}), do: {-1, 0, 0}
  defp sort_key({:joker_teammate, _color, teammate}), do: {-1, 1, teammate}
  defp sort_key({:backward, {_color, idx}, n}), do: {idx, 0, n}
  defp sort_key({:forward, {_color, idx}, n}), do: {idx, 1, n}
  defp sort_key({:joker, {_color, idx}, target}), do: {idx, 2, target}

  @doc """
  The indexes (into `moves`) of the moves that start with the clicked marbles, in click order.
  """
  @spec matching(Board.t(), list({list(Board.step()), Board.t()}), list(Board.marble())) ::
          list(non_neg_integer())
  def matching(board, moves, picked) do
    for {{steps, _new_board}, index} <- Enum.with_index(moves),
        targets_left(board, steps, picked) != nil,
        do: index
  end

  @doc "The marbles that can be clicked next."
  @spec clickable(Board.t(), list({list(Board.step()), Board.t()}), list(Board.marble())) ::
          list(Board.marble())
  def clickable(board, moves, picked) do
    for {steps, _new_board} <- moves,
        [next | _] <- [targets_left(board, steps, picked)],
        marble <- marbles(board, next),
        uniq: true,
        do: marble
  end

  # the targets still to click for a move, or nil if it doesn't start with the picked marbles
  defp targets_left(board, steps, picked) do
    picked = Enum.map(picked, &target(board, &1))

    case Enum.split(targets(board, steps), length(picked)) do
      {^picked, rest} -> rest
      _other_move -> nil
    end
  end

  defp marbles(board, {:barn, color}) do
    for {:barn, idx} <- Enum.with_index(board.marbles[color]), do: {color, idx}
  end

  defp marbles(_board, marble), do: [marble]
end
