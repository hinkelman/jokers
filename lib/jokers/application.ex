defmodule Jokers.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JokersWeb.Telemetry,
      Jokers.Repo,
      {DNSCluster, query: Application.get_env(:jokers, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jokers.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Jokers.Finch},
      # Start a worker by calling: Jokers.Worker.start_link(arg)
      # {Jokers.Worker, arg},
      # Start to serve requests, typically the last entry
      JokersWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jokers.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JokersWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
