defmodule JokersWeb.GameLive.Index do
  @moduledoc "The lobby: start a new game or join one with its code."

  use JokersWeb, :live_view

  alias Jokers.GameServer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Jokers", form: to_form(%{"code" => ""}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md space-y-10">
      <.header>
        New game
        <:subtitle>Start a game, then send the link to everyone playing.</:subtitle>
      </.header>
      <div class="flex gap-4">
        <.button phx-click="new" phx-value-players="4">4 players</.button>
        <.button phx-click="new" phx-value-players="6">6 players</.button>
      </div>

      <.header>Join a game</.header>
      <.simple_form for={@form} phx-submit="join">
        <.input field={@form[:code]} label="Game code" autocomplete="off" />
        <:actions>
          <.button>Join</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def handle_event("new", %{"players" => players}, socket) do
    code = new_code()
    {:ok, _pid} = GameServer.start(code, String.to_integer(players))
    {:noreply, push_navigate(socket, to: ~p"/games/#{code}")}
  end

  def handle_event("join", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.downcase()

    if GameServer.exists?(code) do
      {:noreply, push_navigate(socket, to: ~p"/games/#{code}")}
    else
      {:noreply, put_flash(socket, :error, "No game with the code \"#{code}\".")}
    end
  end

  # six hex characters, easy enough to read out to someone
  defp new_code, do: :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
end
