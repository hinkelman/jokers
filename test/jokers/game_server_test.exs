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
    assert GameServer.claim(id, :red, "ann", "Annie") == :ok
    assert GameServer.names(id) == %{red: "Annie"}
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
end
