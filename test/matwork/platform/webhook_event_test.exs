defmodule Matwork.Platform.WebhookEventTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Platform
  alias Matwork.Platform.SystemActor

  @system %SystemActor{}

  test "record is idempotent on (provider, external_id)" do
    {:ok, first} =
      Platform.record_webhook_event(:mux, "evt_1", %{"type" => "video.asset.ready"},
        actor: @system
      )

    {:ok, second} =
      Platform.record_webhook_event(:mux, "evt_1", %{"type" => "video.asset.ready"},
        actor: @system
      )

    assert first.id == second.id

    count =
      Matwork.Platform.WebhookEvent
      |> Ash.count!(actor: @system)

    assert count == 1
  end

  test "mark_processed sets processed_at" do
    {:ok, event} =
      Platform.record_webhook_event(:mux, "evt_2", %{"type" => "x"}, actor: @system)

    {:ok, processed} = Platform.mark_webhook_processed(event, actor: @system)
    refute is_nil(processed.processed_at)
  end

  test "a normal user cannot read or record webhook events" do
    user = generate(user())

    assert {:error, %Ash.Error.Forbidden{}} =
             Platform.record_webhook_event(:mux, "evt_3", %{}, actor: user)
  end
end
