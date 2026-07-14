defmodule Matwork.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MatworkWeb.Telemetry,
      Matwork.Repo,
      {DNSCluster, query: Application.get_env(:matwork, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:matwork, :ash_domains),
         Application.fetch_env!(:matwork, Oban)
       )},
      {Phoenix.PubSub, name: Matwork.PubSub},
      # Start a worker by calling: Matwork.Worker.start_link(arg)
      # {Matwork.Worker, arg},
      # Start to serve requests, typically the last entry
      MatworkWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :matwork]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Matwork.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MatworkWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
