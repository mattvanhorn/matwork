defmodule Matwork.Media.Jobs.ProcessMuxWebhook do
  @moduledoc """
  Processes one recorded Mux `WebhookEvent`: resolves the tenant from the
  event's `passthrough` (the gym_id we set at upload time), applies the matching
  `Video` transition as the system actor, marks the event processed, and
  broadcasts `{:video_updated, video_id}` so open builder LiveViews refresh.
  Idempotent: a re-run of an already-processed event is a no-op.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Matwork.Media
  alias Matwork.Platform
  alias Matwork.Platform.SystemActor

  @system %SystemActor{}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => id}}) do
    {:ok, event} = Platform.get_webhook_event(id, actor: @system)

    if event.processed_at do
      :ok
    else
      :ok = handle(event.payload)
      {:ok, _} = Platform.mark_webhook_processed(event, actor: @system)
      :ok
    end
  end

  defp handle(%{"type" => "video.asset.ready", "data" => data}) do
    tenant = data["passthrough"]
    playback_id = data |> Map.get("playback_ids", []) |> List.first() |> playback_id()

    with_video(tenant, data["upload_id"], fn video ->
      Media.mark_video_ready(
        video,
        %{
          mux_asset_id: data["id"],
          mux_playback_id: playback_id,
          duration_seconds: duration(data["duration"])
        },
        actor: @system,
        tenant: tenant
      )
    end)
  end

  defp handle(%{"type" => "video.upload.asset_created", "data" => data}) do
    tenant = data["passthrough"]

    # NOTE: for this event, `data` is the Upload resource, not the Asset —
    # its own id (`data["id"]`) IS the upload id; unlike the asset.ready /
    # asset.errored events below, there is no separate `upload_id` field here.
    with_video(tenant, data["id"], fn video ->
      Media.mark_video_processing(video, %{mux_asset_id: data["asset_id"]},
        actor: @system,
        tenant: tenant
      )
    end)
  end

  defp handle(%{"type" => "video.asset.errored", "data" => data}) do
    tenant = data["passthrough"]

    with_video(tenant, data["upload_id"], fn video ->
      Media.mark_video_errored(video, actor: @system, tenant: tenant)
    end)
  end

  # Unhandled event types are recorded (for audit/replay) but need no action.
  defp handle(_payload), do: :ok

  defp with_video(nil, _upload_id, _fun), do: :ok
  defp with_video(_tenant, nil, _fun), do: :ok

  defp with_video(tenant, upload_id, fun) do
    case Media.get_video_by_upload_id(upload_id, actor: @system, tenant: tenant) do
      {:ok, video} ->
        {:ok, updated} = fun.(video)
        broadcast(tenant, updated.id)
        :ok

      # The Video may not exist yet (webhook raced the upload record) — let Oban
      # retry via max_attempts by raising, so a later attempt finds it.
      {:error, _} ->
        raise "video for upload #{upload_id} not found in tenant #{tenant}"
    end
  end

  defp broadcast(tenant, video_id) do
    Phoenix.PubSub.broadcast(Matwork.PubSub, "gym:#{tenant}:videos", {:video_updated, video_id})
  end

  defp playback_id(%{"id" => id}), do: id
  defp playback_id(_), do: nil

  defp duration(seconds) when is_number(seconds), do: trunc(seconds)
  defp duration(_), do: nil
end
