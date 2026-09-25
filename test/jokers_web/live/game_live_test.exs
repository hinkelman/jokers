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

  test "a color can only be taken once", %{conn: conn} do
    # two browsers, each with its own player id in its session
    conn = init_test_session(conn, %{player_id: "ann"})
    other = init_test_session(build_conn(), %{player_id: "bob"})

    id = start_game()
    {:ok, _red, _html} = live(conn, ~p"/games/#{id}?color=red")

    {:ok, view, _html} = live(other, ~p"/games/#{id}")
    assert has_element?(view, "div", "taken")
    refute has_element?(view, "a", "red")

    assert {:error, {:live_redirect, _}} = live(other, ~p"/games/#{id}?color=red")

    # the same browser gets its seat back
    {:ok, _red_again, html} = live(conn, ~p"/games/#{id}?color=red")
    assert html =~ "Your turn"
  end

  test "leaving a seat frees it", %{conn: conn} do
    id = start_game()
    {:ok, red, _html} = live(conn, ~p"/games/#{id}?color=red")
    red |> element("button", "Leave seat") |> render_click()
    assert_patch(red, ~p"/games/#{id}")
    assert GameServer.seats(id) == %{}
  end

  test "clicking a marble on the board picks the move", %{conn: conn} do
    id = start_game(deck: List.duplicate(@queen, 162))
    {:ok, red, _html} = live(conn, ~p"/games/#{id}?color=red")

    red |> element("button[phx-value-index=0]", "Q") |> render_click()
    assert has_element?(red, ~s(g[phx-click="pick_marble"][phx-value-color="red"]))
    refute has_element?(red, "button", "Play this move")

    red |> element(~s(g[phx-value-color="red"][phx-value-index="2"])) |> render_click()
    assert has_element?(red, "button", "Play this move")
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
