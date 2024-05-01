defmodule Jokers.CardsTest do
  use ExUnit.Case, async: true

  alias Jokers.Cards

  test "card decks" do
    assert length(Cards.suits()) == 4
    assert length(Cards.cards()) == 13
    # deck includes two jokers
    assert length(Cards.deck_single()) == 54
    # three decks used in a game
    assert length(Cards.decks()) == 162
  end

  test "dealing" do
    draw_pile = Cards.decks()

    deal1 = Cards.deal(draw_pile, [])
    assert length(deal1[:draw_pile]) == 156
    assert length(deal1[:hand]) == 6

    deal2 = Cards.deal(deal1[:draw_pile], [hearts: :queen])
    assert length(deal2[:draw_pile]) == 151
    assert length(deal2[:hand]) == 6
  end

  test "discarding and drawing" do
    hand = [diamonds: 9, hearts: 3, clubs: 3, clubs: 7, clubs: 5, hearts: :ace]
    discard = Cards.discard({:hearts, 3}, hand, [])
    assert hd(discard[:discard_pile]) == {:hearts, 3}
    assert length(discard[:hand]) == 5

    draw1 = Cards.draw([], discard[:hand], Cards.decks())
    assert draw1[:discard_pile] == []
    assert length(draw1[:hand]) == 6
    assert length(draw1[:draw_pile]) == 161

    draw2 = Cards.draw(Cards.decks(), discard[:hand], discard[:discard_pile])
    assert length(draw2[:hand]) == 6
    assert draw2[:discard_pile] == discard[:discard_pile]
    assert length(draw2[:draw_pile]) == 161
  end
end
