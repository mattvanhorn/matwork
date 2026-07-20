defmodule Matwork.Media.Jobs.ProcessMuxWebhookTest do
  use Matwork.DataCase, async: true
  use Oban.Testing, repo: Matwork.Repo

  import Matwork.Generator

  alias Matwork.Media
  alias Matwork.Media.Jobs.ProcessMuxWebhook
  alias Matwork.Platform
  alias Matwork.Platform.SystemActor

  @system %SystemActor{}

  defp ready_payload(gym_id, upload_id) do
    %{
      "type" => "video.asset.ready",
      "id" => "evt_#{upload_id}",
      "data" => %{
        "id" => "asset_1",
        "upload_id" => upload_id,
        "passthrough" => gym_id,
        "duration" => 42.7,
        "playback_ids" => [%{"id" => "pb_1", "policy" => "signed"}]
      }
    }
  end

  test "processing a ready event marks the video ready and processed" do
    gym = generate(gym())
    video = generate(video(gym: gym, mux_upload_id: "upload_ready"))
    payload = ready_payload(gym.id, "upload_ready")

    {:ok, event} =
      Platform.record_webhook_event(:mux, payload["id"], payload, actor: @system)

    assert :ok = perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})

    {:ok, reloaded} = Media.get_video(video.id, actor: @system, tenant: gym.id)
    assert reloaded.status == :ready
    assert reloaded.mux_playback_id == "pb_1"
    assert reloaded.duration_seconds == 42

    {:ok, processed_event} = Platform.get_webhook_event(event.id, actor: @system)
    refute is_nil(processed_event.processed_at)
  end

  test "re-processing an already-processed event is a no-op" do
    gym = generate(gym())
    generate(video(gym: gym, mux_upload_id: "upload_twice"))
    payload = ready_payload(gym.id, "upload_twice")

    {:ok, event} =
      Platform.record_webhook_event(:mux, payload["id"], payload, actor: @system)

    assert :ok = perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})
    assert :ok = perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})
  end

  test "broadcasts to the gym's video topic" do
    gym = generate(gym())
    generate(video(gym: gym, mux_upload_id: "upload_bcast"))
    payload = ready_payload(gym.id, "upload_bcast")

    Phoenix.PubSub.subscribe(Matwork.PubSub, "gym:#{gym.id}:videos")

    {:ok, event} =
      Platform.record_webhook_event(:mux, payload["id"], payload, actor: @system)

    perform_job(ProcessMuxWebhook, %{"webhook_event_id" => event.id})

    assert_receive {:video_updated, _video_id}
  end
end
