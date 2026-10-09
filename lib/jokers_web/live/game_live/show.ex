defmodule JokersWeb.GameLive.Show do
  @moduledoc """
  A game in progress, seen by one player.

  The player's color is in the URL (`/games/:id?color=red`); without it the page asks which
  color to play, and for a name to show on their side of the board. Opening the page with a color claims that seat for this browser's player id
  (see `JokersWeb.Router`), and a seat someone else holds can't be taken. On their turn a player picks a card, then one of its legal moves, which is
  previewed on the board until they confirm it. Instead of picking from the list of moves, they
  can click marbles on the board to narrow it down (see `JokersWeb.MovePicker`). Until the next
  player moves, they can take their move back. Seated players can also chat.

  Above the board, arrows step back and forward through the game's moves, showing the board as
  each one left it. Moves made meanwhile don't change the move being looked at; they only add
  to the count of moves to come back to.
  """

  use JokersWeb, :live_view

  import JokersWeb.BoardComponents

  alias Jokers.{Board, GameServer}
  alias JokersWeb.MovePicker

  @impl true
  def mount(%{"id" => id}, session, socket) do
    if GameServer.exists?(id) do
      # the game process tells every player's page when something changes
      if connected?(socket), do: GameServer.subscribe(id)

      {:ok,
       assign(socket,
         id: id,
         player_id: session["player_id"],
         messages: GameServer.messages(id),
         # messages this page has sent, so the chat box can be cleared after each one
         sent: 0,
         renaming: false,
         # the move whose board is shown (0 for the deal), or nil for the game as it is now
         step: nil,
         # how many moves there were when the player last saw the game as it is now
         seen_moves: 0
       )}
    else
      {:ok,
       socket |> put_flash(:error, "No game with the code \"#{id}\".") |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{id: id, player_id: player_id} = socket.assigns
    seats = GameServer.view(id, nil).board.seats
    color = Enum.find(seats, &(Atom.to_string(&1) == params["color"]))

    case color && GameServer.claim(id, color, player_id) do
      {:error, :taken} ->
        {:noreply,
         socket
         |> put_flash(:error, "Someone else is already playing #{color}.")
         |> push_patch(to: ~p"/games/#{id}")}

      _no_color_or_ok ->
        {:noreply, socket |> assign(color: color) |> load()}
    end
  end

  @impl true
  def handle_info({:game_updated, _id}, socket) do
    %{id: id, color: color, player_id: player_id} = socket.assigns
    socket = load(socket)

    # the seat was given up, perhaps from another tab
    if color && socket.assigns.seats[color] != player_id,
      do: {:noreply, push_patch(socket, to: ~p"/games/#{id}")},
      else: {:noreply, socket}
  end

  def handle_info({:move_undone, _id, mover}, socket) do
    socket = load(socket)

    if mover == socket.assigns.color,
      do: {:noreply, socket},
      else:
        {:noreply,
         put_flash(socket, :info, "#{who(mover, socket.assigns.names)} took back their move.")}
  end

  def handle_info({:names_updated, id}, socket) do
    {:noreply, assign(socket, names: GameServer.names(id))}
  end

  def handle_info({:chat_message, _id, message}, socket) do
    {:noreply, update(socket, :messages, &Enum.take([message | &1], 100))}
  end

  # the game stopped after sitting idle too long
  def handle_info({:game_closed, id}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Game \"#{id}\" was closed after going unplayed for too long.")
     |> push_navigate(to: ~p"/")}
  end

  # fetches this player's view of the game and clears any card or move they had picked
  defp load(socket) do
    %{id: id, color: color} = socket.assigns
    view = GameServer.view(id, color)

    moves =
      if color && view.turn == color do
        id
        |> GameServer.legal_moves(color)
        |> Map.new(fn {card, card_moves} -> {card, MovePicker.sort(card_moves)} end)
      else
        %{}
      end

    moves_made = length(view.history)

    step =
      case socket.assigns[:step] do
        # an undo or a new deal can leave fewer moves than the one being looked at
        step when is_integer(step) and moves_made > 0 -> min(step, moves_made)
        _live_or_new_deal -> nil
      end

    assign(socket,
      step: step,
      seen_moves: if(step, do: socket.assigns.seen_moves, else: moves_made),
      # the tab's title says when it's your turn, for players looking at another tab
      page_title:
        if(color && view.turn == color, do: "Your turn! · Jokers", else: "Jokers · #{id}"),
      view: view,
      seats: GameServer.seats(id),
      names: GameServer.names(id),
      moves: moves,
      must_discard:
        moves != %{} and Enum.all?(moves, fn {_card, card_moves} -> card_moves == [] end),
      selected_card: nil,
      selected_move: nil,
      picked: []
    )
  end

  @impl true
  def handle_event("sit", %{"color" => color, "name" => name}, socket) do
    %{id: id, player_id: player_id, view: view} = socket.assigns
    color = Enum.find(view.board.seats, &(Atom.to_string(&1) == color))

    case color && GameServer.claim(id, color, player_id, name) do
      :ok ->
        {:noreply, push_patch(socket, to: ~p"/games/#{id}?color=#{color}")}

      _taken_or_no_color ->
        {:noreply, socket |> put_flash(:error, "That color is already taken.") |> load()}
    end
  end

  def handle_event("start_rename", _params, socket) do
    {:noreply, assign(socket, renaming: true)}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, renaming: false)}
  end

  def handle_event("rename", %{"name" => name}, socket) do
    %{id: id, color: color, player_id: player_id} = socket.assigns

    case GameServer.claim(id, color, player_id, name) do
      :ok ->
        {:noreply, assign(socket, renaming: false, names: GameServer.names(id))}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, "You no longer hold #{color}.") |> load()}
    end
  end

  def handle_event("chat", %{"text" => text}, socket) do
    %{id: id, color: color, player_id: player_id} = socket.assigns

    case GameServer.say(id, color, player_id, text) do
      :ok -> {:noreply, update(socket, :sent, &(&1 + 1))}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  # picking a card brings the player back to the game as it is now, to play on it
  def handle_event("select_card", %{"index" => index}, socket) do
    {:noreply,
     assign(socket,
       selected_card: String.to_integer(index),
       selected_move: nil,
       picked: [],
       step: nil
     )}
  end

  # steps through the moves so far; stepping forward past the latest one goes back to now
  def handle_event("history", %{"to" => to}, socket) do
    %{step: step, view: view, color: color} = socket.assigns
    moves_made = length(view.history)

    step =
      case to do
        "back" -> max((step || moves_made + 1) - 1, 0)
        "forward" when step != nil and step < moves_made -> step + 1
        "mine" -> my_last_move(view.history, color) || step
        _forward_or_live -> nil
      end

    {:noreply, assign(socket, step: step, selected_card: nil, selected_move: nil, picked: [])}
  end

  # a marble clicked on the board narrows down the moves; once only one is left, preview it
  def handle_event("pick_marble", %{"color" => color, "index" => index}, socket) do
    %{assigns: assigns} = socket
    marble = {String.to_existing_atom(color), String.to_integer(index)}
    card_moves = card_moves(assigns)

    if marble in MovePicker.clickable(assigns.view.board, card_moves, assigns.picked) do
      picked = assigns.picked ++ [marble]

      selected_move =
        case MovePicker.matching(assigns.view.board, card_moves, picked) do
          [only] -> only
          _several -> nil
        end

      {:noreply, assign(socket, picked: picked, selected_move: selected_move)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_move", %{"index" => index}, socket) do
    {:noreply, assign(socket, selected_move: String.to_integer(index))}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, selected_move: nil, picked: [])}
  end

  def handle_event("play", _params, socket) do
    %{id: id, color: color} = socket.assigns
    {steps, _board} = selected_move(socket.assigns)
    result(socket, GameServer.play(id, color, selected_card(socket.assigns), steps))
  end

  def handle_event("discard", _params, socket) do
    %{id: id, color: color} = socket.assigns
    result(socket, GameServer.discard(id, color, selected_card(socket.assigns)))
  end

  def handle_event("leave", _params, socket) do
    %{id: id, color: color, player_id: player_id} = socket.assigns
    :ok = GameServer.release(id, color, player_id)
    {:noreply, push_patch(socket, to: ~p"/games/#{id}")}
  end

  def handle_event("undo", _params, socket) do
    %{id: id, color: color} = socket.assigns

    case GameServer.undo(id, color) do
      :ok ->
        {:noreply, socket}

      {:error, :too_late} ->
        {:noreply,
         socket |> put_flash(:error, "Too late: the next player has already moved.") |> load()}
    end
  end

  def handle_event("next_game", _params, socket) do
    result(socket, GameServer.next_game(socket.assigns.id))
  end

  # the page reloads when the game broadcasts the change, so only errors need handling here
  defp result(socket, :ok), do: {:noreply, socket}

  defp result(socket, {:error, reason}) do
    {:noreply, socket |> put_flash(:error, "That didn't work (#{reason}).") |> load()}
  end

  defp selected_card(%{selected_card: nil}), do: nil
  defp selected_card(assigns), do: Enum.at(assigns.view.hand, assigns.selected_card)

  defp card_moves(assigns), do: Map.get(assigns.moves, selected_card(assigns), [])

  defp selected_move(%{selected_move: nil}), do: nil
  defp selected_move(assigns), do: Enum.at(card_moves(assigns), assigns.selected_move)

  @impl true
  def render(%{color: nil} = assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-6">
      <.header>
        Game <%= @id %>
        <:subtitle>Share this page's link with the other players. Which color are you?</:subtitle>
      </.header>
      <form id="sit" phx-submit="sit" class="space-y-4">
        <label class="block text-sm font-semibold text-zinc-800">
          Your name <span class="font-normal text-zinc-500">(optional)</span>
          <input
            type="text"
            name="name"
            value={own_name(@seats, @names, @player_id)}
            maxlength="20"
            autocomplete="off"
            class="mt-1 block w-full rounded-lg border-zinc-300 text-zinc-900 focus:border-zinc-400 focus:ring-0 sm:text-sm"
          />
        </label>
        <div class="grid grid-cols-2 gap-3">
          <%= for color <- @view.board.seats do %>
            <% holder = @seats[color] %>
            <button
              :if={holder in [nil, @player_id]}
              name="color"
              value={color}
              class="flex items-center gap-3 rounded-lg border border-zinc-300 p-3 text-left font-semibold hover:bg-zinc-50"
            >
              <.seat_marble color={color} />
              <%= color %>
              <span class="ml-auto text-xs font-normal text-zinc-500">
                <%= if holder, do: "yours", else: "free" %>
              </span>
            </button>
            <div
              :if={holder not in [nil, @player_id]}
              class="flex items-center gap-3 rounded-lg border border-zinc-200 bg-zinc-100 p-3 font-semibold text-zinc-400"
            >
              <.seat_marble color={color} />
              <%= color %>
              <span class="ml-auto text-xs font-normal"><%= @names[color] || "taken" %></span>
            </div>
          <% end %>
        </div>
      </form>
      <p class="text-sm text-zinc-600">
        Teams: <%= team_names(@view.board, 0) %> against <%= team_names(@view.board, 1) %>.
      </p>
    </div>
    """
  end

  def render(%{step: step} = assigns) when step != nil do
    %{view: view} = assigns
    entry = if step > 0, do: Enum.at(view.history, step - 1)

    assigns =
      assign(assigns,
        shown_board: if(entry, do: entry.after, else: hd(view.history).before),
        shown_last_played:
          if(entry, do: entry.last_played, else: Map.new(view.board.seats, &{&1, nil})),
        # the marbles the move moved, so they're easy to find
        highlight: if(entry, do: changed_marbles(entry.before, entry.after), else: []),
        clickable: [],
        preview: nil,
        card_moves: [],
        shown_moves: []
      )

    game_page(assigns)
  end

  def render(assigns) do
    preview = selected_move(assigns)
    board = assigns.view.board
    card_moves = card_moves(assigns)
    picking = assigns.view.turn == assigns.color and card_moves != [] and preview == nil

    assigns =
      assign(assigns,
        preview: preview,
        shown_board: if(preview, do: elem(preview, 1), else: board),
        shown_last_played: assigns.view.last_played,
        highlight:
          if(preview, do: changed_marbles(board, elem(preview, 1)), else: assigns.picked),
        clickable:
          if(picking, do: MovePicker.clickable(board, card_moves, assigns.picked), else: []),
        card_moves: card_moves,
        shown_moves: MovePicker.matching(board, card_moves, assigns.picked)
      )

    game_page(assigns)
  end

  defp game_page(assigns) do
    assigns = assign(assigns, my_last_move: my_last_move(assigns.view.history, assigns.color))

    ~H"""
    <div class="flex flex-col gap-8 lg:flex-row">
      <div class={[
        "lg:w-3/5 rounded-xl ring-offset-4",
        @view.turn == @color && "ring-4 ring-amber-400"
      ]}>
        <div
          :if={@view.history != []}
          id="history"
          class={[
            "mb-2 flex flex-wrap items-center gap-2 rounded-lg px-2 py-1 text-sm",
            if(@step, do: "bg-sky-100 text-sky-950", else: "bg-zinc-100 text-zinc-700")
          ]}
        >
          <button
            type="button"
            phx-click="history"
            phx-value-to="back"
            disabled={@step == 0}
            aria-label="Previous move"
            class="rounded p-1 hover:bg-white/70 disabled:opacity-30"
          >
            <.icon name="hero-chevron-left" class="h-5 w-5" />
          </button>
          <button
            type="button"
            phx-click="history"
            phx-value-to="forward"
            disabled={@step == nil}
            aria-label="Next move"
            class="rounded p-1 hover:bg-white/70 disabled:opacity-30"
          >
            <.icon name="hero-chevron-right" class="h-5 w-5" />
          </button>
          <span id="history-label" class="min-w-0 flex-1">
            <%= history_label(@view.history, @step, @color, @names) %>
          </span>
          <button
            :if={@my_last_move && @step != @my_last_move}
            type="button"
            phx-click="history"
            phx-value-to="mine"
            class="underline hover:no-underline"
          >
            My last move
          </button>
          <button
            :if={@step}
            type="button"
            phx-click="history"
            phx-value-to="live"
            class="rounded-md bg-sky-700 px-2 py-1 font-semibold text-white hover:bg-sky-600"
          >
            Back to now
            <%= case length(@view.history) - @seen_moves do %>
              <% 0 -> %>
              <% 1 -> %>
                (1 new move)
              <% new -> %>
                (<%= new %> new moves)
            <% end %>
          </button>
        </div>
        <.board
          board={@shown_board}
          viewer={@color}
          highlight={@highlight}
          clickable={@clickable}
          last_played={@shown_last_played}
          names={@names}
        />
        <p :if={@preview} class="text-center text-sm font-semibold text-zinc-700">
          Preview of your move: the marbles it moves have a thick border.
        </p>
      </div>

      <div class="space-y-6 lg:w-2/5">
        <div>
          <p class="text-sm text-zinc-500">
            Game <%= @id %> · you are
            <span class="font-semibold" style={"color: #{line_color(@color)}"}><%= @color %></span>
            <%= if @names[@color] do %>
              as <span class="font-semibold text-zinc-700"><%= @names[@color] %></span>
            <% end %>
            <%= if Board.acting_color(@view.board, @color) not in [@color, nil] do %>
              (helping <%= Board.acting_color(@view.board, @color) %>)
            <% end %>
            ·
            <button
              :if={not @renaming}
              type="button"
              phx-click="start_rename"
              class="underline hover:text-zinc-700"
            >
              <%= if @names[@color], do: "Change name", else: "Add name" %>
            </button>
            <span :if={not @renaming}>·</span>
            <button
              type="button"
              phx-click={JS.dispatch("jokers:test-tone")}
              class="underline hover:text-zinc-700"
            >
              Test sound
            </button>
            ·
            <button
              type="button"
              phx-click="leave"
              data-confirm="Give up your seat so someone else can take it?"
              class="underline hover:text-zinc-700"
            >
              Leave seat
            </button>
          </p>
          <form :if={@renaming} id="rename" phx-submit="rename" class="mt-2 flex gap-2">
            <input
              type="text"
              name="name"
              value={@names[@color]}
              maxlength="20"
              autocomplete="off"
              aria-label="Your name"
              phx-mounted={JS.focus()}
              class="block w-full rounded-lg border-zinc-300 text-zinc-900 focus:border-zinc-400 focus:ring-0 sm:text-sm"
            />
            <.button>Save</.button>
            <.button type="button" phx-click="cancel_rename" class="bg-zinc-500 hover:bg-zinc-400">
              Cancel
            </.button>
          </form>
          <%!-- the TurnAlert hook (assets/js/app.js) plays a tone when the turn comes to you --%>
          <p
            id="turn-status"
            phx-hook="TurnAlert"
            data-my-turn={to_string(@view.turn == @color)}
            class="text-xl font-semibold"
          >
            <%= cond do %>
              <% @view.winners -> %>
                <%= Enum.map_join(@view.winners, " & ", &who(&1, @names)) %> win!
              <% @view.turn == @color -> %>
                Your turn
              <% true -> %>
                Waiting for <%= who(@view.turn, @names) %>
            <% end %>
          </p>
          <.button :if={@view.winners} phx-click="next_game" class="mt-2">Deal the next game</.button>
          <div :if={@view.can_undo} class="mt-3 flex items-center gap-3 text-sm text-zinc-600">
            <span>
              Changed your mind? You can take your move back until <%= if @view.turn,
                do: "#{who(@view.turn, @names)} moves",
                else: "the next game is dealt" %>.
            </span>
            <.button phx-click="undo" class="shrink-0 bg-zinc-500 hover:bg-zinc-400">
              Undo my move
            </.button>
          </div>
        </div>

        <div>
          <p class="mb-2 text-sm font-semibold">Your hand</p>
          <div class="flex flex-wrap gap-2">
            <.card
              :for={{card, index} <- Enum.with_index(@view.hand)}
              card={card}
              selected={index == @selected_card}
              phx-click="select_card"
              phx-value-index={index}
            />
            <div
              :if={@view.hidden_draw}
              id="hidden-draw"
              aria-label="The card you drew, hidden for now"
              class="flex h-20 w-14 items-center justify-center rounded-lg border-2 border-zinc-300 bg-zinc-200 text-xl font-bold text-zinc-400"
            >
              ?
            </div>
          </div>
          <p :if={@view.hidden_draw} class="mt-2 text-xs text-zinc-500">
            The card you drew shows once you can no longer undo your move.
          </p>
        </div>

        <div :if={@view.turn == @color and @must_discard} class="space-y-2">
          <p>
            None of your cards can be played. Pick a card to discard.
            <%= if @view.discard_counts[@color] == 4 do %>
              This is your 5th discard in a row, so a marble comes out.
            <% end %>
          </p>
          <.button :if={@selected_card} phx-click="discard">
            Discard <%= card_name(Enum.at(@view.hand, @selected_card)) %>
          </.button>
        </div>

        <div :if={@view.turn == @color and not @must_discard and @selected_card} class="space-y-2">
          <p :if={@card_moves == []}>That card can't be played right now.</p>
          <p :if={@clickable != []} class="text-sm text-zinc-600">
            Click a marble with a dashed ring, or pick a move below.
            <button :if={@picked != []} type="button" phx-click="cancel" class="underline">
              Start over
            </button>
          </p>
          <ul class="max-h-80 space-y-1 overflow-y-auto">
            <li :for={index <- @shown_moves}>
              <button
                type="button"
                phx-click="select_move"
                phx-value-index={index}
                class={[
                  "w-full rounded-md border px-3 py-2 text-left text-sm",
                  if(index == @selected_move,
                    do: "border-zinc-900 bg-zinc-100",
                    else: "border-zinc-200 hover:bg-zinc-50"
                  )
                ]}
              >
                <%= describe_move(@view.board, @card_moves |> Enum.at(index) |> elem(0)) %>
              </button>
            </li>
          </ul>
          <div :if={@preview} class="flex gap-2">
            <.button phx-click="play">Play this move</.button>
            <.button phx-click="cancel" class="bg-zinc-500 hover:bg-zinc-400">Cancel</.button>
          </div>
        </div>

        <p :if={@view.discard_counts[@color] > 0} class="text-sm text-zinc-600">
          Your discards in a row: <%= @view.discard_counts[@color] %>
        </p>

        <div>
          <p class="mb-2 text-sm font-semibold">Chat</p>
          <%!-- reversed so the newest message sits at the bottom and stays in view --%>
          <div
            id="messages"
            class="flex h-48 flex-col-reverse overflow-y-auto rounded-md border border-zinc-200 p-2 text-sm"
          >
            <p :for={message <- @messages} class="break-words">
              <span class="font-semibold" style={"color: #{line_color(message.color)}"}>
                <%= message.name || message.color %>:
              </span>
              <%= message.text %>
            </p>
            <p :if={@messages == []} class="text-zinc-400">No messages yet.</p>
          </div>
          <%!-- a new id after each message replaces the form, which clears the box --%>
          <form id={"chat-#{@sent}"} phx-submit="chat" class="mt-2 flex gap-2">
            <input
              id={"chat-text-#{@sent}"}
              type="text"
              name="text"
              maxlength="300"
              autocomplete="off"
              placeholder="Say something"
              aria-label="Chat message"
              phx-mounted={@sent > 0 && JS.focus()}
              class="block w-full rounded-lg border-zinc-300 text-zinc-900 focus:border-zinc-400 focus:ring-0 sm:text-sm"
            />
            <.button>Send</.button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  attr :color, :atom, required: true

  defp seat_marble(assigns) do
    ~H"""
    <span
      class="h-6 w-6 rounded-full border border-zinc-500"
      style={"background: #{marble_color(@color)}"}
    />
    """
  end

  # the number of the player's latest move, counting from 1
  defp my_last_move(history, color) do
    history
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.find_value(fn {entry, n} -> entry.player == color && n end)
  end

  defp history_label(history, nil, color, names) do
    "Now · last move: " <> describe_entry(List.last(history), color, names)
  end

  defp history_label(_history, 0, _color, _names), do: "Start of the game"

  defp history_label(history, step, color, names) do
    "Move #{step} of #{length(history)}: " <>
      describe_entry(Enum.at(history, step - 1), color, names)
  end

  defp describe_entry(entry, color, names) do
    mover = if entry.player == color, do: "You", else: to_string(who(entry.player, names))

    cond do
      not entry.discard -> "#{mover} played #{card_name(entry.card)}"
      entry.before == entry.after -> "#{mover} discarded #{card_name(entry.card)}"
      true -> "#{mover} discarded #{card_name(entry.card)} (5th in a row, so a marble came out)"
    end
  end

  # a player's name, or their color if they didn't give one
  defp who(color, names), do: names[color] || color

  # the name this browser gave for a seat it holds, to fill in the name box
  defp own_name(seats, names, player_id) do
    Enum.find_value(seats, fn {color, holder} -> holder == player_id && names[color] end)
  end

  defp team_names(board, team) do
    board.seats |> Enum.drop(team) |> Enum.take_every(2) |> Enum.join(" & ")
  end
end
