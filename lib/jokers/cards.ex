defmodule Jokers.Cards do

  def suits() do
    [:hearts, :spades, :clubs, :diamonds]
  end

  def cards() do
    [2, 3, 4, 5, 6, 7, 8, 9, 10, :jack, :queen, :king, :ace]
  end

  @spec deck_single() :: list(tuple)
  def deck_single() do
    x = for suit <- suits(), card <- cards(), do: {suit, card}
    [{:red, :joker} | [{:black, :joker} | x]]
  end

  @spec decks() :: list(tuple)
  def decks() do
    List.flatten([deck_single(), deck_single(), deck_single()])
    |> Enum.shuffle()
  end

  @spec deal(list(tuple), list(tuple)) :: %{draw_pile: list(tuple), hand: list(tuple)}
  def deal([head | tail], hand) when length(hand) < 6 do
    deal(tail, [head | hand])
  end

  def deal(draw_pile, hand) when length(hand) > 5 do
    # don't need to handle empty list for deal b/c only deal at start of game
    %{draw_pile: draw_pile, hand: hand}
  end

  @spec draw(list(tuple), list(tuple), list(tuple)) :: %{draw_pile: list(tuple), discard_pile: list(tuple), hand: list(tuple)}
  def draw([head | tail], hand, discard_pile) do
    %{draw_pile: tail, hand: [head | hand], discard_pile: discard_pile}
  end

  def draw([], hand, discard_pile) do
    x = Enum.shuffle(discard_pile)
    %{draw_pile: tl(x), hand: [hd(x) | hand], discard_pile: []}
  end

  @spec discard(tuple(), list(tuple), list(tuple)) :: %{hand: list(tuple), discard_pile: list(tuple)}
  def discard(card, hand, discard_pile) do
    new_hand = Enum.filter(hand, fn c -> c != card end)
    %{hand: new_hand, discard_pile: [card | discard_pile]}
  end
end
