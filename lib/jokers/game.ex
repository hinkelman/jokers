defmodule Jokers.Game do
  @moduledoc """
  One game of Jokers: the board, the cards, and whose turn it is.

  These are plain functions on a `%Game{}` struct; `Jokers.GameServer` keeps a game in a
  process so every player sees the same one.
  """

  alias Jokers.{Board, Cards}

  @discards_to_come_out 5

  defstruct [
    :board,
    :dealer,
    # nil once the game is over
    :turn,
    # the colors on the winning team, once there is one
    :winners,
    hands: %{},
    draw_pile: [],
    discard_pile: [],
    # consecutive discards for each player
    discard_counts: %{}
  ]

  @type t :: %__MODULE__{
          board: Board.t(),
          dealer: Board.color(),
          turn: Board.color() | nil,
          winners: list(Board.color()) | nil,
          hands: %{Board.color() => list(tuple)},
          draw_pile: list(tuple),
          discard_pile: list(tuple),
          discard_counts: %{Board.color() => non_neg_integer()}
        }

  @type error :: :game_over | :not_your_turn | :not_in_hand | :must_play | :illegal_move

  @doc """
  Deals a new game. Options:

    * `:dealer` - the dealing color (defaults to the last seat, so the first seat plays first)
    * `:deck` - the cards to deal from, top card first (defaults to three shuffled decks)
  """
  @spec new(4 | 6, keyword()) :: t()
  def new(player_num, opts \\ []) do
    board = Board.new(player_num)
    dealer = Keyword.get(opts, :dealer, List.last(board.seats))
    first = next_seat(board, dealer)

    {hands, draw_pile} =
      board.seats
      |> rotate_to(first)
      |> Enum.reduce({%{}, Keyword.get(opts, :deck, Cards.decks())}, fn color, {hands, pile} ->
        %{hand: hand, draw_pile: pile} = Cards.deal(pile, [])
        {Map.put(hands, color, hand), pile}
      end)

    %__MODULE__{
      board: board,
      dealer: dealer,
      turn: first,
      hands: hands,
      draw_pile: draw_pile,
      discard_counts: Map.new(board.seats, &{&1, 0})
    }
  end

  @doc "Deals the next game; the deal passes to the player on the dealer's left."
  @spec next_game(t()) :: t()
  def next_game(game) do
    new(length(game.board.seats), dealer: next_seat(game.board, game.dealer))
  end

  @doc "The legal moves for each card in a player's hand (see `Jokers.Board.legal_moves/3`)."
  @spec legal_moves(t(), Board.color()) :: %{tuple => list({list(Board.step()), Board.t()})}
  def legal_moves(game, player) do
    game.hands[player]
    |> Enum.uniq()
    |> Map.new(&{&1, Board.legal_moves(game.board, player, &1)})
  end

  @doc "True when none of the player's cards can be played, so they have to discard."
  @spec must_discard?(t(), Board.color()) :: boolean()
  def must_discard?(game, player) do
    game |> legal_moves(player) |> Enum.all?(fn {_card, moves} -> moves == [] end)
  end

  @spec play(t(), Board.color(), tuple(), list(Board.step())) :: {:ok, t()} | {:error, error()}
  def play(game, player, card, steps) do
    with :ok <- check_turn(game, player),
         :ok <- check_card(game, player, card),
         {:ok, board} <- Board.play(game.board, player, card, steps) do
      game = %{game | board: board, discard_counts: Map.put(game.discard_counts, player, 0)}
      {:ok, end_turn(game, player, card)}
    end
  end

  @doc "Discards a card face up. Only allowed when the player has no legal move."
  @spec discard(t(), Board.color(), tuple()) :: {:ok, t()} | {:error, error()}
  def discard(game, player, card) do
    with :ok <- check_turn(game, player),
         :ok <- check_card(game, player, card),
         :ok <- if(must_discard?(game, player), do: :ok, else: {:error, :must_play}) do
      count = game.discard_counts[player] + 1

      game =
        if count == @discards_to_come_out do
          # the 5th discard in a row brings a marble out, if one can come out
          board =
            case Board.come_out(game.board, Board.acting_color(game.board, player)) do
              {:ok, board} -> board
              :error -> game.board
            end

          %{game | board: board, discard_counts: Map.put(game.discard_counts, player, 0)}
        else
          %{game | discard_counts: Map.put(game.discard_counts, player, count)}
        end

      {:ok, end_turn(game, player, card)}
    end
  end

  @doc """
  What `player` is allowed to see: everything except the other players' hands, which are
  shown only as a number of cards.
  """
  @spec view(t(), Board.color()) :: map()
  def view(game, player) do
    %{
      board: game.board,
      dealer: game.dealer,
      turn: game.turn,
      winners: game.winners,
      hand: game.hands[player],
      hand_sizes: Map.new(game.hands, fn {color, hand} -> {color, length(hand)} end),
      draw_pile_size: length(game.draw_pile),
      discard_pile: game.discard_pile,
      discard_counts: game.discard_counts
    }
  end

  defp check_turn(%{winners: winners}, _player) when winners != nil, do: {:error, :game_over}
  defp check_turn(%{turn: player}, player), do: :ok
  defp check_turn(_game, _player), do: {:error, :not_your_turn}

  defp check_card(game, player, card) do
    if card in game.hands[player], do: :ok, else: {:error, :not_in_hand}
  end

  # the played or discarded card goes on the discard pile, the player draws, and play
  # passes to the left unless the player's team has won
  defp end_turn(game, player, card) do
    %{hand: hand, discard_pile: discard_pile} =
      Cards.discard(card, game.hands[player], game.discard_pile)

    %{hand: hand, draw_pile: draw_pile, discard_pile: discard_pile} =
      Cards.draw(game.draw_pile, hand, discard_pile)

    game = %{
      game
      | hands: Map.put(game.hands, player, hand),
        draw_pile: draw_pile,
        discard_pile: discard_pile
    }

    if Board.team_won?(game.board, player) do
      %{game | winners: [player | Board.teammates(game.board, player)], turn: nil}
    else
      %{game | turn: next_seat(game.board, player)}
    end
  end

  defp next_seat(board, color) do
    rotate_to(board.seats, color) |> Enum.at(1)
  end

  # the seats in turn order, starting with `color`
  defp rotate_to(seats, color) do
    {before, rest} = Enum.split_while(seats, &(&1 != color))
    rest ++ before
  end
end
