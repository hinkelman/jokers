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
end
