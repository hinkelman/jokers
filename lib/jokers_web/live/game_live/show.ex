defmodule JokersWeb.GameLive.Show do
  @moduledoc """
  A game in progress, seen by one player.

  The player's color is in the URL (`/games/:id?color=red`); without it the page asks which
  color to play. Opening the page with a color claims that seat for this browser's player id
  (see `JokersWeb.Router`), and a seat someone else holds can't be taken. On their turn a player picks a card, then one of its legal moves, which is
  previewed on the board until they confirm it.
  """

  use JokersWeb, :live_view

  import JokersWeb.BoardComponents

  alias Jokers.{Board, GameServer}

  @impl true
  def mount(%{"id" => id}, session, socket) do
    if GameServer.exists?(id) do
      # the game process tells every player's page when something changes
      if connected?(socket), do: GameServer.subscribe(id)
      {:ok, assign(socket, id: id, player_id: session["player_id"], page_title: "Jokers · #{id}")}
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

  # fetches this player's view of the game and clears any card or move they had picked
  defp load(socket) do
    %{id: id, color: color} = socket.assigns
    view = GameServer.view(id, color)
    moves = if color && view.turn == color, do: GameServer.legal_moves(id, color), else: %{}

    assign(socket,
      view: view,
      seats: GameServer.seats(id),
      moves: moves,
      must_discard:
        moves != %{} and Enum.all?(moves, fn {_card, card_moves} -> card_moves == [] end),
      selected_card: nil,
      selected_move: nil
    )
  end

  @impl true
  def handle_event("select_card", %{"index" => index}, socket) do
    {:noreply, assign(socket, selected_card: String.to_integer(index), selected_move: nil)}
  end

  def handle_event("select_move", %{"index" => index}, socket) do
    {:noreply, assign(socket, selected_move: String.to_integer(index))}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, selected_move: nil)}
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

  # marbles whose position differs between two boards
  defp changed_marbles(before, after_move) do
    for {color, positions} <- before.marbles,
        {{old, new}, idx} <- Enum.with_index(Enum.zip(positions, after_move.marbles[color])),
        old != new,
        do: {color, idx}
  end

  @impl true
  def render(%{color: nil} = assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-6">
      <.header>
        Game <%= @id %>
        <:subtitle>Share this page's link with the other players. Which color are you?</:subtitle>
      </.header>
      <div class="grid grid-cols-2 gap-3">
        <%= for color <- @view.board.seats do %>
          <% holder = @seats[color] %>
          <.link
            :if={holder in [nil, @player_id]}
            patch={~p"/games/#{@id}?color=#{color}"}
            class="flex items-center gap-3 rounded-lg border border-zinc-300 p-3 font-semibold hover:bg-zinc-50"
          >
            <.seat_marble color={color} />
            <%= color %>
            <span class="ml-auto text-xs font-normal text-zinc-500">
              <%= if holder, do: "yours", else: "free" %>
            </span>
          </.link>
          <div
            :if={holder not in [nil, @player_id]}
            class="flex items-center gap-3 rounded-lg border border-zinc-200 bg-zinc-100 p-3 font-semibold text-zinc-400"
          >
            <.seat_marble color={color} />
            <%= color %>
            <span class="ml-auto text-xs font-normal">taken</span>
          </div>
        <% end %>
      </div>
      <p class="text-sm text-zinc-600">
        Teams: <%= team_names(@view.board, 0) %> against <%= team_names(@view.board, 1) %>.
      </p>
    </div>
    """
  end

  def render(assigns) do
    preview = selected_move(assigns)

    assigns =
      assign(assigns,
        preview: preview,
        shown_board: if(preview, do: elem(preview, 1), else: assigns.view.board),
        highlight:
          if(preview, do: changed_marbles(assigns.view.board, elem(preview, 1)), else: []),
        card_moves: card_moves(assigns)
      )

    ~H"""
    <div class="flex flex-col gap-8 lg:flex-row">
      <div class="lg:w-3/5">
        <.board board={@shown_board} viewer={@color} highlight={@highlight} />
        <p :if={@preview} class="text-center text-sm font-semibold text-orange-600">
          Preview of your move: changed marbles are ringed in orange.
        </p>
      </div>

      <div class="space-y-6 lg:w-2/5">
        <div>
          <p class="text-sm text-zinc-500">
            Game <%= @id %> · you are
            <span class="font-semibold" style={"color: #{line_color(@color)}"}><%= @color %></span>
            <%= if Board.acting_color(@view.board, @color) not in [@color, nil] do %>
              (helping <%= Board.acting_color(@view.board, @color) %>)
            <% end %>
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
          <p class="text-xl font-semibold">
            <%= cond do %>
              <% @view.winners -> %>
                <%= Enum.join(@view.winners, " & ") %> win!
              <% @view.turn == @color -> %>
                Your turn
              <% true -> %>
                Waiting for <%= @view.turn %>
            <% end %>
          </p>
          <.button :if={@view.winners} phx-click="next_game" class="mt-2">Deal the next game</.button>
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
          </div>
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
          <ul class="max-h-80 space-y-1 overflow-y-auto">
            <li :for={{{steps, _board}, index} <- Enum.with_index(@card_moves)}>
              <button
                type="button"
                phx-click="select_move"
                phx-value-index={index}
                class={[
                  "w-full rounded-md border px-3 py-2 text-left text-sm",
                  if(index == @selected_move,
                    do: "border-orange-500 bg-orange-50",
                    else: "border-zinc-200 hover:bg-zinc-50"
                  )
                ]}
              >
                <%= describe_move(@view.board, steps) %>
              </button>
            </li>
          </ul>
          <div :if={@preview} class="flex gap-2">
            <.button phx-click="play">Play this move</.button>
            <.button phx-click="cancel" class="bg-zinc-500 hover:bg-zinc-400">Cancel</.button>
          </div>
        </div>

        <div class="space-y-1 text-sm text-zinc-600">
          <p>
            Discard pile:
            <%= case @view.discard_pile do %>
              <% [top | _] -> %>
                <span class="font-semibold"><%= card_name(top) %></span>
              <% [] -> %>
                empty
            <% end %>
            · draw pile: <%= @view.draw_pile_size %> cards
          </p>
          <p>Dealer: <%= @view.dealer %></p>
          <p :if={@view.discard_counts[@color] > 0}>
            Your discards in a row: <%= @view.discard_counts[@color] %>
          </p>
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

  defp team_names(board, team) do
    board.seats |> Enum.drop(team) |> Enum.take_every(2) |> Enum.join(" & ")
  end
end
