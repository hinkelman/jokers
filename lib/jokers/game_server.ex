defmodule Jokers.GameServer do
  @moduledoc """
  Keeps one `Jokers.Game` in its own process, so every player's browser works with the same game.

  Each game is registered under an id in `Jokers.GameRegistry` and started under
  `Jokers.GameSupervisor`. After every change the server broadcasts `{:game_updated, id}` on
  the game's PubSub topic. The message doesn't include the game, because each player may only
  see their own hand; subscribers call `view/2` to fetch what they are allowed to see.

  The server also keeps track of who is sitting in each seat: a color is claimed by a player
  id (one per browser), and nobody else can claim it until it is released. Seated players may
  give a name to show on their side of the board (a name change alone is broadcast as
  `{:names_updated, id}`, so pages needn't reload the game), and can send chat messages, which are
  broadcast as `{:chat_message, id, message}` so pages can add them without reloading the game.

  The player who moved last may take the move back until the next player moves (or, after a
  winning move, until the next game is dealt). The server keeps the game as it was before that
  move, and until the chance to undo has passed, the card the player drew is hidden from them,
  so they can't pick a different move knowing what they'll draw. An undo is broadcast as
  `{:move_undone, id, color}`.

  A game nobody has touched for `@idle_timeout` (or the `:idle_timeout` option) stops itself,
  so abandoned games don't pile up. Before stopping it broadcasts `{:game_closed, id}` so any
  page still open on it can send its player back to the lobby.
  """

  # :temporary because a restarted game would be a brand new deal, not the game in progress
  use GenServer, restart: :temporary

  alias Jokers.Game

  @max_name 20
  @max_message 300
  # only the most recent messages are kept, so a long chat can't grow forever
  @max_messages 100

  # long enough to survive a break between hands, short enough that abandoned games go away
  @idle_timeout :timer.hours(12)

  ## Client API

  @spec start(term(), 4 | 6, keyword()) :: DynamicSupervisor.on_start_child()
  def start(id, player_num, opts \\ []) do
    DynamicSupervisor.start_child(Jokers.GameSupervisor, {__MODULE__, {id, player_num, opts}})
  end

  def start_link({id, player_num, opts}) do
    GenServer.start_link(__MODULE__, {id, player_num, opts}, name: via(id))
  end

  @spec exists?(term()) :: boolean()
  def exists?(id), do: Registry.lookup(Jokers.GameRegistry, id) != []

  @spec subscribe(term()) :: :ok | {:error, term()}
  def subscribe(id), do: Phoenix.PubSub.subscribe(Jokers.PubSub, topic(id))

  def view(id, player), do: GenServer.call(via(id), {:view, player})
  def legal_moves(id, player), do: GenServer.call(via(id), {:legal_moves, player})
  def play(id, player, card, steps), do: GenServer.call(via(id), {:play, player, card, steps})
  def discard(id, player, card), do: GenServer.call(via(id), {:discard, player, card})
  def next_game(id), do: GenServer.call(via(id), :next_game)

  @doc "Takes back `player`'s last move, if the next player hasn't moved yet."
  @spec undo(term(), atom()) :: :ok | {:error, :too_late}
  def undo(id, player), do: GenServer.call(via(id), {:undo, player})

  @doc "Which player id holds each claimed color."
  @spec seats(term()) :: %{atom() => String.t()}
  def seats(id), do: GenServer.call(via(id), :seats)

  @doc """
  Claims a color for a player. Claiming a color you already hold is fine. A `name` replaces the
  name shown for the seat; without one the seat keeps the name it has.
  """
  @spec claim(term(), atom(), String.t(), String.t() | nil) ::
          :ok | {:error, :taken | :no_such_color}
  def claim(id, color, player_id, name \\ nil),
    do: GenServer.call(via(id), {:claim, color, player_id, name})

  @doc "The name each seated player gave, by color."
  @spec names(term()) :: %{atom() => String.t()}
  def names(id), do: GenServer.call(via(id), :names)

  @doc "Sends a chat message from the player holding `color`."
  @spec say(term(), atom(), String.t(), String.t()) :: :ok | {:error, :not_seated | :empty}
  def say(id, color, player_id, text), do: GenServer.call(via(id), {:say, color, player_id, text})

  @doc "The chat messages so far, newest first."
  @spec messages(term()) :: [%{color: atom(), name: String.t() | nil, text: String.t()}]
  def messages(id), do: GenServer.call(via(id), :messages)

  @doc "Gives up a color the player holds, so someone else can claim it."
  @spec release(term(), atom(), String.t()) :: :ok
  def release(id, color, player_id), do: GenServer.call(via(id), {:release, color, player_id})

  defp via(id), do: {:via, Registry, {Jokers.GameRegistry, id}}
  defp topic(id), do: "game:#{inspect(id)}"

  ## Server callbacks

  @impl true
  def init({id, player_num, opts}) do
    {idle_timeout, opts} = Keyword.pop(opts, :idle_timeout, @idle_timeout)
    state = %{id: id, game: Game.new(player_num, opts), seats: %{}, names: %{}, messages: []}
    # undo is the player who moved last and the game from before their move, while they can
    # still take it back
    state = Map.merge(state, %{undo: nil, idle_timeout: idle_timeout})
    {:ok, state, idle_timeout}
  end

  @impl true
  def handle_call({:view, player}, _from, state) do
    view = Game.view(state.game, player)
    can_undo = state.undo != nil and state.undo.player == player
    # a drawn card goes on the front of the hand
    view = if can_undo, do: %{view | hand: tl(view.hand)}, else: view
    reply(Map.merge(view, %{can_undo: can_undo, hidden_draw: can_undo}), state)
  end

  def handle_call({:legal_moves, player}, _from, state) do
    reply(Game.legal_moves(state.game, player), state)
  end

  def handle_call({:play, player, card, steps}, _from, state) do
    update(state, Game.play(state.game, player, card, steps), player)
  end

  def handle_call({:discard, player, card}, _from, state) do
    update(state, Game.discard(state.game, player, card), player)
  end

  def handle_call(:next_game, _from, state) do
    update(state, {:ok, Game.next_game(state.game)}, nil)
  end

  def handle_call({:undo, player}, _from, state) do
    case state.undo do
      %{player: ^player, game: game} ->
        state = %{state | game: game, undo: nil}
        Phoenix.PubSub.broadcast(Jokers.PubSub, topic(state.id), {:move_undone, state.id, player})
        reply(:ok, state)

      _other_player_or_none ->
        reply({:error, :too_late}, state)
    end
  end

  def handle_call(:seats, _from, state), do: reply(state.seats, state)

  def handle_call(:names, _from, state), do: reply(state.names, state)
  def handle_call(:messages, _from, state), do: reply(state.messages, state)

  def handle_call({:claim, color, player_id, name}, _from, state) do
    cond do
      color not in state.game.board.seats ->
        reply({:error, :no_such_color}, state)

      Map.get(state.seats, color, player_id) != player_id ->
        reply({:error, :taken}, state)

      true ->
        new_state = %{state | seats: Map.put(state.seats, color, player_id)}
        new_state = if name, do: put_name(new_state, color, name), else: new_state

        cond do
          new_state.seats != state.seats -> broadcast(new_state)
          new_state.names != state.names -> broadcast(new_state, :names_updated)
          true -> :nothing_changed
        end

        reply(:ok, new_state)
    end
  end

  def handle_call({:release, color, player_id}, _from, state) do
    if state.seats[color] == player_id do
      state = %{
        state
        | seats: Map.delete(state.seats, color),
          names: Map.delete(state.names, color)
      }

      broadcast(state)
      reply(:ok, state)
    else
      reply(:ok, state)
    end
  end

  def handle_call({:say, color, player_id, text}, _from, state) do
    text = text |> String.trim() |> String.slice(0, @max_message)

    cond do
      state.seats[color] != player_id ->
        reply({:error, :not_seated}, state)

      text == "" ->
        reply({:error, :empty}, state)

      true ->
        message = %{color: color, name: state.names[color], text: text}
        messages = Enum.take([message | state.messages], @max_messages)

        Phoenix.PubSub.broadcast(
          Jokers.PubSub,
          topic(state.id),
          {:chat_message, state.id, message}
        )

        reply(:ok, %{state | messages: messages})
    end
  end

  # a blank name clears the seat's name
  defp put_name(state, color, name) do
    case name |> String.trim() |> String.slice(0, @max_name) do
      "" -> %{state | names: Map.delete(state.names, color)}
      name -> %{state | names: Map.put(state.names, color, name)}
    end
  end

  # `mover` is the player who can take this change back, if anyone
  defp update(state, {:ok, game}, mover) do
    undo = if mover, do: %{player: mover, game: state.game}
    state = %{state | game: game, undo: undo}
    broadcast(state)
    reply(:ok, state)
  end

  defp update(state, {:error, _reason} = error, _mover), do: reply(error, state)

  @impl true
  def handle_info(:timeout, state) do
    Phoenix.PubSub.broadcast(Jokers.PubSub, topic(state.id), {:game_closed, state.id})
    {:stop, :normal, state}
  end

  # every reply restarts the idle countdown
  defp reply(result, state), do: {:reply, result, state, state.idle_timeout}

  defp broadcast(state, event \\ :game_updated) do
    Phoenix.PubSub.broadcast(Jokers.PubSub, topic(state.id), {event, state.id})
  end
end
