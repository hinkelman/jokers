defmodule Jokers.Colors do
  @moduledoc """
  Provides colors based on number of players and defines order that marbles move around the board.
  """

  @spec get(number()) :: list(atom)
  def get(player_num) when player_num == 4 do
    # orders of the colors going counter-clockwise around the board
    # the color on the left in the (wrapping) list is the same as left on the board
    [:blue, :yellow, :black, :red]
  end

  def get(player_num) when player_num == 6 do
    [:green, :white, :blue, :yellow, :black, :red]
  end

  @spec get_next(list(atom), atom(), :left | :right) :: atom()
  def get_next(colors, color, side) when side == :right do
    # add first element to the *end* of colors
    [List.first(colors) | Enum.reverse(colors)]
    |> Enum.reverse()
    |> get_right(color)
  end

  def get_next(colors, color, side) when side == :left do
    # add last element to beginning of colors and reverse to use get_right
    [List.last(colors) | colors]
    |> Enum.reverse()
    |> get_right(color)
  end

  # https://elixirforum.com/t/getting-adjacent-values-from-a-list/37256
  defp get_right([], _color), do: nil
  defp get_right([head, right | _], color) when head == color, do: right
  defp get_right([_head | tail], color), do: get_right(tail, color)

  # two teams of two or three
  # when all your marbles are home, you play marbles of teammate on your left
  @spec get_next_teammate(list(atom), atom(), map()) :: atom()
  def get_next_teammate(colors, color, _homes) when length(colors) == 4 do
    get_next_teammate_helper(colors, color)
  end

  # when playing with two teams of three, you sequentially help the teammates on your left
  def get_next_teammate(colors, color, homes) when length(colors) == 6 do
    tm_left = get_next_teammate_helper(colors, color)
    # check if all marbles are in home
    if Enum.any?(homes[tm_left], fn {_k, v} -> v == nil end) do
      tm_left
    else
      get_next_teammate_helper(colors, tm_left)
    end
  end

  defp get_next_teammate_helper(colors, color) do
    opp_left = get_next(colors, color, :left)
    get_next(colors, opp_left, :left)
  end
end
