defmodule Mahjong.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MahjongWeb.Telemetry,
      Mahjong.Repo,
      {DNSCluster, query: Application.get_env(:mahjong, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mahjong.PubSub},
      # Start a worker by calling: Mahjong.Worker.start_link(arg)
      # {Mahjong.Worker, arg},
      pg_spec(),
      # Start to serve requests, typically the last entry
      MahjongWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mahjong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MahjongWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp pg_spec do
    %{
      id: :pg,
      start: {:pg, :start_link, [:global]}
    }
  end
end
