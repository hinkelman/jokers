defmodule JokersWeb.Router do
  use JokersWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JokersWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_player_id
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JokersWeb do
    pipe_through :browser

    live "/", GameLive.Index
    live "/games/:id", GameLive.Show
  end

  # Gives each browser a random id, kept in the session cookie, so a player keeps their seat
  # in a game when they reload the page.
  defp put_player_id(conn, _opts) do
    if get_session(conn, :player_id) do
      conn
    else
      put_session(conn, :player_id, Base.url_encode64(:crypto.strong_rand_bytes(16)))
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", JokersWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jokers, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JokersWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
