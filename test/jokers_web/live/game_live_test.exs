defmodule JokersWeb.GameLiveTest do
  use JokersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Jokers.GameServer

  @queen {:hearts, :queen}

  defp start_game(opts \\ []) do
    id = "test-#{System.unique_integer([:positive])}"
    {:ok, _pid} = GameServer.start(id, 4, opts)
    id
  end

  test "starting a new game", %{conn: conn} do
    {:ok, lobby, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: "/games/" <> code}}} =
             render_click(lobby, "new", %{"players" => "4"})

    assert GameServer.exists?(code)
  end

  test "joining a game that doesn't exist", %{conn: conn} do
    {:ok, lobby, _html} = live(conn, ~p"/")
    assert render_submit(lobby, "join", %{"code" => "nope"}) =~ "No game with the code"
  end

  test "picking a color", %{conn: conn} do
    id = start_game()
    {:ok, view, html} = live(conn, ~p"/games/#{id}")
    assert html =~ "Which color are you?"

    view |> element("a", "yellow") |> render_click()
    assert_patch(view, ~p"/games/#{id}?color=yellow")
    assert render(view) =~ "Waiting for red"
  end

  test "playing a card updates every player's page", %{conn: conn} do
    id = start_game(deck: List.duplicate(@queen, 162))
    {:ok, red, _html} = live(conn, ~p"/games/#{id}?color=red")
    {:ok, black, _html} = live(conn, ~p"/games/#{id}?color=black")
    assert render(red) =~ "Your turn"

    red |> element("button[phx-value-index=0]", "Q") |> render_click()
    assert render(red) =~ "bring a red marble out"
    red |> element("li button", "bring a red marble out") |> render_click()
    red |> element("button", "Play this move") |> render_click()

    assert render(red) =~ "Waiting for black"
    assert render(black) =~ "Your turn"
  end
end
