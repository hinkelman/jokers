defmodule Jokers.GameServer do
  @moduledoc """
  Keeps one `Jokers.Game` in its own process, so every player's browser works with the same game.

  Each game is registered under an id in `Jokers.GameRegistry` and started under
  `Jokers.GameSupervisor`. After every change the server broadcasts `{:game_updated, id}` on
  the game's PubSub topic. The message doesn't include the game, because each player may only
  see their own hand; subscribers call `view/2` to fetch what they are allowed to see.
  """

  # :temporary because a restarted game would be a brand new deal, not the game in progress
  use GenServer, restart: :temporary

  alias Jokers.Game

  ## Client API

  @spec start(term(), 4 | 6, keyword()) :: DynamicSupervisor.on_start_child()
  def start(id, player_num, opts \\ []) do
    DynamicSupervisor.start_child(Jokers.GameSupervisor, {__MODULE__, {id, player_num, opts}})
  end

  def start_link({id, player_num, opts}) do
    GenServer.start_link(__MODULE__, {id, player_num, opts}, name: via(id))
  end

  @spec subscribe(term()) :: :ok | {:error, term()}
  def subscribe(id), do: Phoenix.PubSub.subscribe(Jokers.PubSub, topic(id))

  def view(id, player), do: GenServer.call(via(id), {:view, player})
  def legal_moves(id, player), do: GenServer.call(via(id), {:legal_moves, player})
  def play(id, player, card, steps), do: GenServer.call(via(id), {:play, player, card, steps})
  def discard(id, player, card), do: GenServer.call(via(id), {:discard, player, card})
  def next_game(id), do: GenServer.call(via(id), :next_game)

  defp via(id), do: {:via, Registry, {Jokers.GameRegistry, id}}
  defp topic(id), do: "game:#{inspect(id)}"

  ## Server callbacks

  @impl true
  def init({id, player_num, opts}) do
    {:ok, %{id: id, game: Game.new(player_num, opts)}}
  end

  @impl true
  def handle_call({:view, player}, _from, state) do
    {:reply, Game.view(state.game, player), state}
  end

  def handle_call({:legal_moves, player}, _from, state) do
    {:reply, Game.legal_moves(state.game, player), state}
  end

  def handle_call({:play, player, card, steps}, _from, state) do
    update(state, Game.play(state.game, player, card, steps))
  end

  def handle_call({:discard, player, card}, _from, state) do
    update(state, Game.discard(state.game, player, card))
  end

  def handle_call(:next_game, _from, state) do
    update(state, {:ok, Game.next_game(state.game)})
  end

  defp update(state, {:ok, game}) do
    Phoenix.PubSub.broadcast(Jokers.PubSub, topic(state.id), {:game_updated, state.id})
    {:reply, :ok, %{state | game: game}}
  end

  defp update(state, {:error, _reason} = error), do: {:reply, error, state}
end
