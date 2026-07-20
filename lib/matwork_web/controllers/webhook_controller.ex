defmodule MatworkWeb.WebhookController do
  use MatworkWeb, :controller

  require Logger

  alias Matwork.Media.Jobs.ProcessMuxWebhook
  alias Matwork.Platform
  alias Matwork.Platform.Mux.Signature
  alias Matwork.Platform.SystemActor
  alias MatworkWeb.Plugs.CacheRawBody

  @system %SystemActor{}

  def mux(conn, params) do
    raw_body = CacheRawBody.raw_body(conn)
    signature = conn |> get_req_header("mux-signature") |> List.first()
    secret = Application.fetch_env!(:matwork, :mux_webhook_secret)

    case Signature.verify(raw_body, signature, secret) do
      :ok -> record_and_enqueue(conn, params)
      :error -> send_resp(conn, 400, "invalid signature")
    end
  end

  defp record_and_enqueue(conn, %{"id" => external_id} = params) do
    case Platform.record_webhook_event(:mux, external_id, params, actor: @system) do
      {:ok, event} ->
        enqueue_processing(conn, event, external_id)

      {:error, reason} ->
        Logger.error(
          "Mux webhook record failed external_id=#{external_id} reason=#{inspect(reason)}"
        )

        send_resp(conn, 200, "")
    end
  end

  # A Mux webhook always carries a top-level "id"; anything else is noise.
  defp record_and_enqueue(conn, _params), do: send_resp(conn, 400, "missing id")

  defp enqueue_processing(conn, event, external_id) do
    case %{"webhook_event_id" => event.id} |> ProcessMuxWebhook.new() |> Oban.insert() do
      {:ok, _job} ->
        send_resp(conn, 200, "")

      {:error, reason} ->
        Logger.error(
          "Mux webhook enqueue failed webhook_event_id=#{event.id} external_id=#{external_id} reason=#{inspect(reason)}"
        )

        send_resp(conn, 200, "")
    end
  end
end
