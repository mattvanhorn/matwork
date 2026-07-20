defmodule Matwork.Platform.Mux do
  @moduledoc """
  The single boundary for the Mux API (per CLAUDE.md — no direct HTTP/SDK
  calls to Mux anywhere else). Defines the behaviour and dispatches to the
  configured implementation (`Platform.Mux.HTTP` in dev/prod, `MuxMock` in
  tests).

  Signature verification is NOT here — it is local HMAC, see
  `Matwork.Platform.Mux.Signature`. Signed-playback JWT minting is Session 3.
  """

  @doc "Create a Mux direct upload. `params` may include `:passthrough` and `:cors_origin`."
  @callback create_direct_upload(params :: map()) ::
              {:ok, %{id: String.t(), url: String.t()}} | {:error, term()}

  @doc "Fetch a Mux asset by id (used to reconcile state if needed)."
  @callback get_asset(asset_id :: String.t()) :: {:ok, map()} | {:error, term()}

  def create_direct_upload(params \\ %{}), do: impl().create_direct_upload(params)
  def get_asset(asset_id), do: impl().get_asset(asset_id)

  defp impl, do: Application.get_env(:matwork, :mux, Matwork.Platform.Mux.HTTP)
end
