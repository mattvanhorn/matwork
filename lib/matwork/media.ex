defmodule Matwork.Media do
  @moduledoc "The Media domain: Mux-backed videos and their upload lifecycle."
  use Ash.Domain, otp_app: :matwork

  alias Ash.Error.Forbidden
  alias Matwork.Platform.Mux

  resources do
    resource Matwork.Media.Video do
      define :create_video, action: :create, args: [:mux_upload_id, :title]
      define :get_video, action: :read, get_by: [:id]
      define :get_video_by_upload_id, action: :by_upload_id, args: [:mux_upload_id]
      define :mark_video_processing, action: :mark_processing
      define :mark_video_ready, action: :mark_ready
      define :mark_video_errored, action: :mark_errored
    end
  end

  @doc """
  Start a Mux direct upload for the current tenant and record a `Video` in
  `:pending_upload`. Returns `{:ok, {video, upload_url}}`; the caller hands
  `upload_url` to the browser (via the MuxUpload JS hook) — video bytes never
  touch the server. `opts` must include `:actor` and `:tenant`.

  Authorization is checked *before* calling Mux — a forbidden caller must
  never trigger an outbound Mux API call.
  """
  def create_direct_upload(title, opts) do
    tenant = Keyword.fetch!(opts, :tenant)
    actor = Keyword.get(opts, :actor)

    with true <- Ash.can?({Matwork.Media.Video, :create}, actor, tenant: tenant),
         {:ok, %{id: upload_id, url: upload_url}} <-
           Mux.create_direct_upload(%{passthrough: tenant}),
         {:ok, video} <- create_video(upload_id, title, opts) do
      {:ok, {video, upload_url}}
    else
      false -> {:error, Forbidden.exception([])}
      {:error, _} = error -> error
    end
  end
end
