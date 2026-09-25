defmodule Jokers.Board do
  @moduledoc """
  Board state and marble movement. RULES.md describes the rules implemented here.

  A marble's position is one of:

    * `:barn` - in its owner's barn
    * `{:track, index}` - on the shared track; `index` counts forward (clockwise) from
      position 0 of the first seat's side, so each side covers 18 consecutive indexes
    * `{:house, slot}` - in its owner's house; slot 1 is next to the home door, slot 5 is the last

  A marble is identified by `{color, index}` where `index` is 0 to 4.
  """

  alias Jokers.Colors

  @side_length 18
  @barn_door 8
  @home_door 3
  @house_size 5
  @marble_count 5

  # seats are in clockwise (turn) order, so the seat after a player is the player on their left
  defstruct seats: [], marbles: %{}

  @type color :: atom()
  @type position :: :barn | {:track, non_neg_integer()} | {:house, 1..5}
  @type marble :: {color(), non_neg_integer()}
  @type step ::
          {:forward, marble(), pos_integer()}
          | {:backward, marble(), pos_integer()}
          | {:come_out, color()}
          | {:joker, marble(), position()}
          | {:joker_teammate, color(), color()}
  @type t :: %__MODULE__{seats: list(color()), marbles: %{color() => list(position())}}

  @spec new(4 | 6) :: t()
  def new(player_num) when player_num in [4, 6] do
    # Colors.get lists colors counter-clockwise
    seats = player_num |> Colors.get() |> Enum.reverse()
    marbles = Map.new(seats, fn color -> {color, List.duplicate(:barn, @marble_count)} end)
    %__MODULE__{seats: seats, marbles: marbles}
  end

  ## Geometry

  @spec track_length(t()) :: pos_integer()
  def track_length(board), do: length(board.seats) * @side_length

  @doc "Track position `pos` (0 to 17) on the side of the board belonging to `color`."
  @spec track(t(), color(), 0..17) :: position()
  def track(board, color, pos) when pos in 0..17 do
    {:track, seat(board, color) * @side_length + pos}
  end

  @doc "The inverse of `track/3`: which side a track position is on and its number on that side."
  @spec side_position(t(), position()) :: {color(), 0..17}
  def side_position(board, {:track, index}) do
    {Enum.at(board.seats, div(index, @side_length)), rem(index, @side_length)}
  end

  @spec barn_door(t(), color()) :: position()
  def barn_door(board, color), do: track(board, color, @barn_door)

  @spec home_door(t(), color()) :: position()
  def home_door(board, color), do: track(board, color, @home_door)

  defp seat(board, color), do: Enum.find_index(board.seats, &(&1 == color))

  # number of forward steps along the track from one index to another
  defp distance(board, from, to), do: rem(to - from + track_length(board), track_length(board))

  ## Teams

  @spec teammates?(t(), color(), color()) :: boolean()
  def teammates?(board, a, b), do: rem(seat(board, a), 2) == rem(seat(board, b), 2)

  @doc "The other players on `color`'s team, in the order they are helped (starting on the left)."
  @spec teammates(t(), color()) :: list(color())
  def teammates(board, color) do
    n = length(board.seats)
    s = seat(board, color)
    for k <- 2..(n - 2)//2, do: Enum.at(board.seats, rem(s + k, n))
  end

  @spec finished?(t(), color()) :: boolean()
  def finished?(board, color), do: Enum.all?(board.marbles[color], &match?({:house, _}, &1))

  @doc """
  The color whose marbles `player` moves: their own until all of them are home, then the
  teammates they help. Returns nil when the whole team is home.
  """
  @spec acting_color(t(), color()) :: color() | nil
  def acting_color(board, player) do
    Enum.find([player | teammates(board, player)], &(not finished?(board, &1)))
  end

  @spec team_won?(t(), color()) :: boolean()
  def team_won?(board, player), do: acting_color(board, player) == nil

  ## Marbles

  @spec position(t(), marble()) :: position()
  def position(board, {color, idx}), do: Enum.at(board.marbles[color], idx)

  @doc "Puts a marble at a position without applying any rules (for setting up a board)."
  @spec place(t(), marble(), position()) :: t()
  def place(board, {color, idx}, position) do
    %{board | marbles: Map.update!(board.marbles, color, &List.replace_at(&1, idx, position))}
  end

  defp occupant(board, {:track, _} = position) do
    Enum.find_value(board.marbles, fn {color, positions} ->
      case Enum.find_index(positions, &(&1 == position)) do
        nil -> nil
        idx -> {color, idx}
      end
    end)
  end

  defp barn_marble(board, color), do: Enum.find_index(board.marbles[color], &(&1 == :barn))

  ## Single moves

  @doc "Moves a marble `n` steps. It may pass marbles of other colors but not its own color."
  @spec move(t(), marble(), pos_integer(), :forward | :backward) :: {:ok, t()} | :error
  def move(board, {color, _} = marble, n, direction) do
    with {:ok, path} <- path(board, color, position(board, marble), n, direction),
         false <- Enum.any?(path, &(&1 in board.marbles[color])) do
      {:ok, land(board, marble, List.last(path))}
    else
      _ -> :error
    end
  end

  @doc "Moves a marble from the barn onto its barn door."
  @spec come_out(t(), color()) :: {:ok, t()} | :error
  def come_out(board, color) do
    door = barn_door(board, color)

    with idx when idx != nil <- barn_marble(board, color),
         false <- door in board.marbles[color] do
      {:ok, land(board, {color, idx}, door)}
    else
      _ -> :error
    end
  end

  @doc """
  Moves a track marble forward directly onto another color's marble. Like any move, it can't
  pass its own color, and it can't go past its home door.
  """
  @spec joker(t(), marble(), position()) :: {:ok, t()} | :error
  def joker(board, {color, _} = marble, {:track, target} = position) do
    {:track, door} = home_door(board, color)

    with {:track, from} = start <- position(board, marble),
         {other, _} when other != color <- occupant(board, position),
         steps = distance(board, from, target),
         true <- steps <= distance(board, from, door),
         {:ok, path} <- path(board, color, start, steps, :forward),
         false <- Enum.any?(path, &(&1 in board.marbles[color])) do
      {:ok, land(board, marble, position)}
    else
      _ -> :error
    end
  end

  @doc "Moves a marble from the barn onto a teammate's barn door when the teammate has a marble there."
  @spec joker_teammate(t(), color(), color()) :: {:ok, t()} | :error
  def joker_teammate(board, color, teammate) do
    with true <- teammate != color and teammates?(board, color, teammate),
         true <- barn_door(board, teammate) in board.marbles[teammate],
         idx when idx != nil <- barn_marble(board, color) do
      {:ok, land(board, {color, idx}, barn_door(board, teammate))}
    else
      _ -> :error
    end
  end

  defp path(board, color, from, n, direction) do
    Enum.reduce_while(1..n//1, [from], fn _, [pos | _] = acc ->
      case next(board, color, pos, direction) do
        nil -> {:halt, :error}
        next_pos -> {:cont, [next_pos | acc]}
      end
    end)
    |> case do
      :error -> :error
      acc -> {:ok, acc |> Enum.reverse() |> tl()}
    end
  end

  defp next(board, color, {:track, index} = pos, :forward) do
    if pos == home_door(board, color),
      do: {:house, 1},
      else: {:track, rem(index + 1, track_length(board))}
  end

  defp next(board, _color, {:track, index}, :backward) do
    {:track, rem(index - 1 + track_length(board), track_length(board))}
  end

  defp next(_board, _color, {:house, slot}, :forward) when slot < @house_size,
    do: {:house, slot + 1}

  defp next(_board, _color, _pos, _direction), do: nil

  # moves a marble to a position, hitting any marble already on that track position
  defp land(board, {color, _} = marble, position) do
    target = if match?({:track, _}, position), do: occupant(board, position)
    board = place(board, marble, position)
    if target, do: hit(board, target, color, position), else: board
  end

  defp hit(board, {color, _} = marble, hitter, position) do
    door = home_door(board, color)

    # a teammate's marble hit on its own home door has nowhere to go but the barn
    if teammates?(board, color, hitter) and position != door do
      # any marble already on the home door goes to its barn
      board =
        case occupant(board, door) do
          nil -> board
          other -> place(board, other, :barn)
        end

      place(board, marble, door)
    else
      place(board, marble, :barn)
    end
  end

  ## Cards

  @doc """
  Every legal way `player` can play `card`, as `{steps, resulting_board}` pairs.
  An empty list means the player has to discard.
  """
  @spec legal_moves(t(), color(), tuple()) :: list({list(step()), t()})
  def legal_moves(board, player, {_suit, rank}) do
    case acting_color(board, player) do
      nil -> []
      color -> moves(board, player, color, rank)
    end
  end

  @doc "Plays a card with the chosen steps, which must be one of the card's legal moves."
  @spec play(t(), color(), tuple(), list(step())) :: {:ok, t()} | {:error, :illegal_move}
  def play(board, player, card, steps) do
    case List.keyfind(legal_moves(board, player, card), steps, 0) do
      {_steps, new_board} -> {:ok, new_board}
      nil -> {:error, :illegal_move}
    end
  end

  defp moves(board, _player, color, n) when n in [2, 3, 4, 5, 6, 10] do
    single_moves(board, color, n, :forward)
  end

  defp moves(board, player, color, 7) do
    single_moves(board, color, 7, :forward) ++
      split_moves(board, player, color, for(a <- 1..6, do: {{:forward, a}, {:forward, 7 - a}}))
  end

  defp moves(board, _player, color, 8), do: single_moves(board, color, 8, :backward)

  defp moves(board, player, color, 9) do
    parts =
      for f <- 1..8, order <- [:forward_first, :backward_first] do
        if order == :forward_first,
          do: {{:forward, f}, {:backward, 9 - f}},
          else: {{:backward, 9 - f}, {:forward, f}}
      end

    split_moves(board, player, color, parts)
  end

  defp moves(board, _player, color, face) when face in [:jack, :queen, :king] do
    single_moves(board, color, 10, :forward) ++ come_out_moves(board, color)
  end

  defp moves(board, _player, color, :ace) do
    single_moves(board, color, 1, :forward) ++
      single_moves(board, color, 11, :forward) ++ come_out_moves(board, color)
  end

  defp moves(board, _player, color, :joker) do
    targets =
      for {other, positions} <- board.marbles,
          other != color,
          {:track, _} = pos <- positions,
          do: pos

    jumps =
      for {{:track, _}, idx} <- Enum.with_index(board.marbles[color]),
          target <- targets,
          {:ok, new_board} <- [joker(board, {color, idx}, target)],
          do: {[{:joker, {color, idx}, target}], new_board}

    teammate_doors =
      for teammate <- teammates(board, color),
          {:ok, new_board} <- [joker_teammate(board, color, teammate)],
          do: {[{:joker_teammate, color, teammate}], new_board}

    jumps ++ teammate_doors ++ come_out_moves(board, color)
  end

  defp single_moves(board, color, n, direction) do
    for {pos, idx} <- Enum.with_index(board.marbles[color]),
        pos != :barn,
        {:ok, new_board} <- [move(board, {color, idx}, n, direction)],
        do: {[{direction, {color, idx}, n}], new_board}
  end

  # two moves by different marbles; if the first move brings the last of the acting color's
  # marbles home, the second move is made with the next teammate's marbles
  defp split_moves(board, player, color, parts) do
    for {{dir1, n1}, {dir2, n2}} <- parts,
        {[{_, marble1, _} = step1], board1} <- single_moves(board, color, n1, dir1),
        {steps, board2} <- second_moves(board1, player, marble1, dir2, n2),
        do: {[step1 | steps], board2}
  end

  defp second_moves(board, player, first_marble, direction, n) do
    case acting_color(board, player) do
      # the first move brought the whole team home, so the rest of the split can't be used
      nil ->
        []

      color ->
        for {[{_, marble, _}], _} = move <- single_moves(board, color, n, direction),
            marble != first_marble,
            do: move
    end
  end

  defp come_out_moves(board, color) do
    case come_out(board, color) do
      {:ok, new_board} -> [{[{:come_out, color}], new_board}]
      :error -> []
    end
  end
end
