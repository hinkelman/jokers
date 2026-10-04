defmodule Jokers.GameServerTest do
  use ExUnit.Case, async: true

  alias Jokers.GameServer

  @queen {:hearts, :queen}

  test "players share one game and are told about changes" do
    id = make_ref()
    {:ok, _pid} = GameServer.start(id, 4, deck: List.duplicate(@queen, 162))
    :ok = GameServer.subscribe(id)

    assert GameServer.view(id, :red).turn == :red
    assert %{@queen => [_]} = GameServer.legal_moves(id, :red)

    assert GameServer.play(id, :red, @queen, [{:come_out, :red}]) == :ok
    assert_receive {:game_updated, ^id}
    assert GameServer.view(id, :black).turn == :black

    assert GameServer.play(id, :red, @queen, [{:come_out, :red}]) == {:error, :not_your_turn}
    refute_receive {:game_updated, ^id}
  end

  test "each color can be claimed by only one player" do
    id = make_ref()
    {:ok, _pid} = GameServer.start(id, 4)
    :ok = GameServer.subscribe(id)

    assert GameServer.claim(id, :red, "ann") == :ok
    assert_receive {:game_updated, ^id}
    # claiming your own seat again is fine
    assert GameServer.claim(id, :red, "ann") == :ok
    assert GameServer.claim(id, :red, "bob") == {:error, :taken}
    assert GameServer.claim(id, :green, "bob") == {:error, :no_such_color}
    assert GameServer.seats(id) == %{red: "ann"}

    # only the holder can release a seat
    assert GameServer.release(id, :red, "bob") == :ok
    assert GameServer.seats(id) == %{red: "ann"}
    assert GameServer.release(id, :red, "ann") == :ok
    assert GameServer.claim(id, :red, "bob") == :ok
  end

  test "a game id can only be started once" do
    id = make_ref()
    {:ok, pid} = GameServer.start(id, 6)
    assert GameServer.start(id, 6) == {:error, {:already_started, pid}}
  end

  test "a game nobody touches stops itself" do
    id = make_ref()
    {:ok, pid} = GameServer.start(id, 4, idle_timeout: 50)
    :ok = GameServer.subscribe(id)
    ref = Process.monitor(pid)

    assert_receive {:game_closed, ^id}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "seated players can give a name" do
    id = make_ref()
    {:ok, _pid} = GameServer.start(id, 4)

    assert GameServer.claim(id, :red, "ann", "  Ann  ") == :ok
    assert GameServer.names(id) == %{red: "Ann"}

    # coming back without a name keeps it, a new one replaces it, and a blank one clears it
    assert GameServer.claim(id, :red, "ann") == :ok
    assert GameServer.names(id) == %{red: "Ann"}
    :ok = GameServer.subscribe(id)
    assert GameServer.claim(id, :red, "ann", "Annie") == :ok
    assert GameServer.names(id) == %{red: "Annie"}
    # a new name alone doesn't make every page reload the game
    assert_receive {:names_updated, ^id}
    refute_received {:game_updated, ^id}
    assert GameServer.claim(id, :red, "ann", " ") == :ok
    assert GameServer.names(id) == %{}

    # someone else can't rename a seat they don't hold, and leaving it drops the name
    assert GameServer.claim(id, :red, "ann", "Ann") == :ok
    assert GameServer.claim(id, :red, "bob", "Bob") == {:error, :taken}
    assert GameServer.release(id, :red, "ann") == :ok
    assert GameServer.names(id) == %{}
  end

  test "seated players can chat" do
    id = make_ref()
    {:ok, _pid} = GameServer.start(id, 4)
    :ok = GameServer.claim(id, :red, "ann", "Ann")
    :ok = GameServer.claim(id, :black, "bob")
    :ok = GameServer.subscribe(id)

    assert GameServer.say(id, :red, "ann", " hi ") == :ok
    assert_receive {:chat_message, ^id, %{color: :red, name: "Ann", text: "hi"}}
    assert GameServer.say(id, :black, "bob", "hello") == :ok
    assert_receive {:chat_message, ^id, %{text: "hello"}}

    assert GameServer.messages(id) == [
             %{color: :black, name: nil, text: "hello"},
             %{color: :red, name: "Ann", text: "hi"}
           ]

    assert GameServer.say(id, :red, "bob", "not my seat") == {:error, :not_seated}
    assert GameServer.say(id, :red, "ann", "   ") == {:error, :empty}
    refute_receive {:chat_message, ^id, _message}
  end

  test "a player can take back their move until the next player moves" do
    id = make_ref()
    {:ok, _pid} = GameServer.start(id, 4, deck: List.duplicate(@queen, 162))
    before = GameServer.view(id, :red)
    refute before.can_undo

    :ok = GameServer.play(id, :red, @queen, [{:come_out, :red}])
    :ok = GameServer.subscribe(id)

    # only red can undo, and red can't see the card they drew until then
    after_move = GameServer.view(id, :red)
    assert after_move.can_undo and after_move.hidden_draw
    assert length(after_move.hand) == length(before.hand) - 1
    refute GameServer.view(id, :black).can_undo
    assert GameServer.undo(id, :black) == {:error, :too_late}

    assert GameServer.undo(id, :red) == :ok
    assert_receive {:move_undone, ^id, :red}
    assert GameServer.view(id, :red) == before
    assert GameServer.undo(id, :red) == {:error, :too_late}

    # once black moves, red's move stands and red sees their new card
    :ok = GameServer.play(id, :red, @queen, [{:come_out, :red}])
    :ok = GameServer.play(id, :black, @queen, [{:come_out, :black}])
    assert GameServer.undo(id, :red) == {:error, :too_late}
    refute GameServer.view(id, :red).hidden_draw
    assert length(GameServer.view(id, :red).hand) == length(before.hand)
    assert GameServer.view(id, :black).can_undo
  end

  test "dealing the next game ends the chance to undo" do
    id = make_ref()
    {:ok, _pid} = GameServer.start(id, 4, deck: List.duplicate(@queen, 162))
    :ok = GameServer.play(id, :red, @queen, [{:come_out, :red}])
    :ok = GameServer.next_game(id)
    assert GameServer.undo(id, :red) == {:error, :too_late}
    refute GameServer.view(id, :red).hidden_draw
  end
end
