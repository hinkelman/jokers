defmodule Jokers.GameTest do
  use ExUnit.Case, async: true

  alias Jokers.{Board, Game}

  @queen {:hearts, :queen}
  @five {:clubs, 5}

  # the default dealer is blue, so red is dealt the first 6 cards and plays first
  defp deck(red_cards), do: red_cards ++ List.duplicate(@five, 162 - length(red_cards))

  test "dealing" do
    game = Game.new(4)
    assert game.dealer == :blue
    assert game.turn == :red
    assert Enum.all?(game.hands, fn {_color, hand} -> length(hand) == 6 end)
    assert length(game.draw_pile) == 162 - 24
    assert Game.new(4, dealer: :red).turn == :black
  end

  test "playing a card" do
    game = Game.new(4, deck: deck(List.duplicate(@queen, 6)))
    assert Game.play(game, :black, @five, []) == {:error, :not_your_turn}
    assert Game.play(game, :red, @five, [{:come_out, :red}]) == {:error, :not_in_hand}
    assert Game.play(game, :red, @queen, [{:come_out, :black}]) == {:error, :illegal_move}
    assert Game.discard(game, :red, @queen) == {:error, :must_play}

    {:ok, game} = Game.play(game, :red, @queen, [{:come_out, :red}])
    assert Board.position(game.board, {:red, 0}) == Board.barn_door(game.board, :red)
    assert length(game.hands[:red]) == 6
    assert hd(game.discard_pile) == @queen
    assert game.turn == :black
  end

  test "the 5th discard in a row brings a marble out" do
    game = Game.new(4, deck: deck([]))

    game =
      Enum.reduce(1..16, game, fn _, game ->
        {:ok, game} = Game.discard(game, game.turn, @five)
        game
      end)

    assert game.discard_counts == %{red: 4, black: 4, yellow: 4, blue: 4}
    {:ok, game} = Game.discard(game, :red, @five)
    assert Board.position(game.board, {:red, 0}) == Board.barn_door(game.board, :red)
    assert game.discard_counts[:red] == 0
    # red can move the marble now
    refute Game.must_discard?(game, :red)
  end

  test "winning" do
    game = Game.new(4, deck: deck([{:hearts, 2}]))

    # red is home, and yellow's last marble is 2 from its last house slot
    placements =
      for(i <- 0..4, do: {{:red, i}, {:house, i + 1}}) ++
        for(i <- 0..3, do: {{:yellow, i}, {:house, i + 2}})

    board =
      Enum.reduce(placements, game.board, fn {marble, pos}, b -> Board.place(b, marble, pos) end)

    board = Board.place(board, {:yellow, 4}, Board.track(board, :yellow, 2))

    game = %{game | board: board}
    {:ok, game} = Game.play(game, :red, {:hearts, 2}, [{:forward, {:yellow, 4}, 2}])
    assert game.winners == [:red, :yellow]
    assert game.turn == nil
    assert Game.discard(game, :black, @five) == {:error, :game_over}

    next = Game.next_game(game)
    assert next.dealer == :red
    assert next.turn == :black
    assert next.winners == nil
  end

  test "a player's view hides the other hands" do
    game = Game.new(4)
    view = Game.view(game, :red)
    assert view.hand == game.hands[:red]
    assert view.hand_sizes == %{red: 6, black: 6, yellow: 6, blue: 6}
    refute Map.has_key?(view, :hands)
  end
end
