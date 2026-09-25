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

  test "a game id can only be started once" do
    id = make_ref()
    {:ok, pid} = GameServer.start(id, 6)
    assert GameServer.start(id, 6) == {:error, {:already_started, pid}}
  end
end
