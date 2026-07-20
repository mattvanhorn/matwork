defmodule Matwork.Platform.MuxTest do
  use ExUnit.Case, async: true

  import Mox

  alias Matwork.Platform.Mux
  alias Matwork.Platform.MuxMock

  setup :verify_on_exit!

  test "create_direct_upload/1 dispatches to the configured impl" do
    MuxMock
    |> expect(:create_direct_upload, fn params ->
      assert params.passthrough == "gym-123"
      {:ok, %{id: "upload_abc", url: "https://storage.example/put"}}
    end)

    assert {:ok, %{id: "upload_abc", url: "https://storage.example/put"}} =
             Mux.create_direct_upload(%{passthrough: "gym-123"})
  end
end
