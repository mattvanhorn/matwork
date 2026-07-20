defmodule Matwork.Platform.Mux.HTTP do
  @moduledoc """
  Req-backed `Platform.Mux` implementation. Talks to the Mux Video API over
  HTTP Basic auth. Never called directly by feature code — always reached via
  `Matwork.Platform.Mux`.
  """
  @behaviour Matwork.Platform.Mux

  @base_url "https://api.mux.com"

  @impl true
  def create_direct_upload(params) do
    body = %{
      cors_origin: Map.get(params, :cors_origin, "*"),
      new_asset_settings: %{
        playback_policy: ["signed"],
        passthrough: Map.get(params, :passthrough)
      }
    }

    case Req.post(req(), url: "/video/v1/uploads", json: body) do
      {:ok, %{status: status, body: %{"data" => data}}} when status in 200..299 ->
        {:ok, %{id: data["id"], url: data["url"]}}

      {:ok, resp} ->
        {:error, {:mux_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_asset(asset_id) do
    case Req.get(req(), url: "/video/v1/assets/#{asset_id}") do
      {:ok, %{status: status, body: %{"data" => data}}} when status in 200..299 ->
        {:ok, data}

      {:ok, resp} ->
        {:error, {:mux_http, resp.status, resp.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req do
    config = Application.get_env(:matwork, __MODULE__, [])
    token_id = Keyword.get(config, :token_id)
    token_secret = Keyword.get(config, :token_secret)

    Req.new(base_url: @base_url, auth: {:basic, "#{token_id}:#{token_secret}"})
  end
end
