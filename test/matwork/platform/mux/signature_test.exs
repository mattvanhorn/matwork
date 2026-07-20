defmodule Matwork.Platform.Mux.SignatureTest do
  use ExUnit.Case, async: true

  alias Matwork.Platform.Mux.Signature

  @secret "test_mux_secret"
  @body ~s({"type":"video.asset.ready","id":"evt_1"})

  defp header(body, secret, t \\ "1600000000") do
    v1 =
      :crypto.mac(:hmac, :sha256, secret, "#{t}.#{body}") |> Base.encode16(case: :lower)

    "t=#{t},v1=#{v1}"
  end

  test "accepts a correctly signed body" do
    assert Signature.verify(@body, header(@body, @secret), @secret) == :ok
  end

  test "rejects a tampered body" do
    assert Signature.verify(@body <> "x", header(@body, @secret), @secret) == :error
  end

  test "rejects a wrong secret" do
    assert Signature.verify(@body, header(@body, "other"), @secret) == :error
  end

  test "rejects a missing/garbage header" do
    assert Signature.verify(@body, nil, @secret) == :error
    assert Signature.verify(@body, "nonsense", @secret) == :error
  end
end
