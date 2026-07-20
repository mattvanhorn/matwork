defmodule MatworkWeb.WebhookControllerTest do
  use MatworkWeb.ConnCase, async: true
  use Oban.Testing, repo: Matwork.Repo

  alias Matwork.Media.Jobs.ProcessMuxWebhook

  @secret "test_mux_secret"

  defp signed(conn, body) do
    t = "1600000000"
    v1 = :crypto.mac(:hmac, :sha256, @secret, "#{t}.#{body}") |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("mux-signature", "t=#{t},v1=#{v1}")
    |> post("/webhooks/mux", body)
  end

  test "a validly signed event is recorded and a job is enqueued", %{conn: conn} do
    body =
      ~s({"type":"video.asset.ready","id":"evt_ctrl_1","data":{"passthrough":"g","upload_id":"u"}})

    conn = signed(conn, body)

    assert response(conn, 200)
    assert_enqueued(worker: ProcessMuxWebhook)
  end

  test "a duplicate delivery enqueues based on one recorded event", %{conn: conn} do
    body =
      ~s({"type":"video.asset.ready","id":"evt_ctrl_dup","data":{"passthrough":"g","upload_id":"u"}})

    signed(conn, body)
    signed(recycle(conn), body)

    count = Matwork.Platform.WebhookEvent |> Ash.count!(actor: %Matwork.Platform.SystemActor{})
    assert count == 1
  end

  test "a badly signed event is rejected", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mux-signature", "t=1600000000,v1=deadbeef")
      |> post("/webhooks/mux", ~s({"type":"x","id":"evt_bad"}))

    assert response(conn, 400)
    refute_enqueued(worker: ProcessMuxWebhook)
  end
end
