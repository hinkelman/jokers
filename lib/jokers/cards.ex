defmodule Jokers.Cards do
  @moduledoc """
  The cards: three shuffled decks, each with two jokers. A card is `{suit, rank}`; a joker is
  `{:red, :joker}` or `{:black, :joker}`.
  """

  @hand_size 6

  def suits, do: [:hearts, :spades, :clubs, :diamonds]

  def ranks, do: [2, 3, 4, 5, 6, 7, 8, 9, 10, :jack, :queen, :king, :ace]

  @spec deck() :: list(tuple)
  def deck do
    [{:red, :joker}, {:black, :joker} | for(suit <- suits(), rank <- ranks(), do: {suit, rank})]
  end

  @spec decks() :: list(tuple)
  def decks, do: Enum.shuffle(deck() ++ deck() ++ deck())

  @doc "Fills a hand up to six cards from the top of the draw pile."
  @spec deal(list(tuple), list(tuple)) :: %{draw_pile: list(tuple), hand: list(tuple)}
  def deal(draw_pile, hand) do
    # only used at the start of a game, so the draw pile never runs out here
    {dealt, draw_pile} = Enum.split(draw_pile, @hand_size - length(hand))
    # each card dealt goes on the front of the hand
    %{draw_pile: draw_pile, hand: Enum.reverse(dealt, hand)}
  end

  @doc "Draws the top card; an empty draw pile is replaced by the shuffled discard pile first."
  @spec draw(list(tuple), list(tuple), list(tuple)) :: %{
          draw_pile: list(tuple),
          discard_pile: list(tuple),
          hand: list(tuple)
        }
  def draw([], hand, discard_pile), do: draw(Enum.shuffle(discard_pile), hand, [])

  def draw([card | draw_pile], hand, discard_pile) do
    %{draw_pile: draw_pile, hand: [card | hand], discard_pile: discard_pile}
  end

  @spec discard(tuple(), list(tuple), list(tuple)) :: %{
          hand: list(tuple),
          discard_pile: list(tuple)
        }
  def discard(card, hand, discard_pile) do
    # List.delete removes only the first match; with three decks a hand can hold duplicate cards
    %{hand: List.delete(hand, card), discard_pile: [card | discard_pile]}
  end
end
