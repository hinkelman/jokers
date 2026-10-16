defmodule Jokers.Stats do
  @moduledoc """
  A summary of a game for each team, worked out from the game's history: the strong cards
  its players played, the opponents' marbles they sent back to the barn, and their discards.
  """

  alias Jokers.Board

  @type t :: %{
          jokers: non_neg_integer(),
          aces: non_neg_integer(),
          faces: non_neg_integer(),
          eights: non_neg_integer(),
          nines: non_neg_integer(),
          knockouts: non_neg_integer(),
          discards: non_neg_integer()
        }

  @empty %{jokers: 0, aces: 0, faces: 0, eights: 0, nines: 0, knockouts: 0, discards: 0}

  @doc """
  The summary for each team, the team of the first seat first. `history` is a game's history,
  oldest first, as in `Jokers.Game.view/2`.
  """
  @spec teams(Board.t(), list(Jokers.Game.history_entry())) :: list(t())
  def teams(board, history) do
    totals =
      Enum.reduce(history, %{0 => @empty, 1 => @empty}, fn entry, totals ->
        Map.update!(totals, team(board, entry.player), &add(&1, board, entry))
      end)

    [totals[0], totals[1]]
  end

  defp add(stats, board, entry) do
    stats
    |> count(card_stat(entry), not entry.discard)
    |> count(:discards, entry.discard)
    # a 5th discard in a row can bring a marble out onto an opponent's, so discards count too
    |> Map.update!(:knockouts, &(&1 + knockouts(board, entry)))
  end

  defp count(stats, key, true) when key != nil, do: Map.update!(stats, key, &(&1 + 1))
  defp count(stats, _key, _counted), do: stats

  defp card_stat(%{card: {_suit, rank}}) do
    case rank do
      :joker -> :jokers
      :ace -> :aces
      rank when rank in [:jack, :queen, :king] -> :faces
      8 -> :eights
      9 -> :nines
      _ -> nil
    end
  end

  # opponents' marbles never leave the barn on someone else's turn, so any more in their barns
  # were hit
  defp knockouts(board, entry) do
    board.seats
    |> Enum.reject(&Board.teammates?(board, &1, entry.player))
    |> Enum.map(&(in_barn(entry.after, &1) - in_barn(entry.before, &1)))
    |> Enum.sum()
  end

  defp in_barn(board, color), do: Enum.count(board.marbles[color], &(&1 == :barn))

  defp team(board, color), do: rem(Enum.find_index(board.seats, &(&1 == color)), 2)
end
