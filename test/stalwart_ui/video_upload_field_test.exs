defmodule StalwartUI.VideoUploadFieldTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.VideoUploadField

  defp field(assigns), do: render_component(&video_upload_field/1, assigns)

  test "renders an upload control when there is no video" do
    html = field(%{lesson_id: "l1", status: nil})
    assert html =~ "No video"
    assert html =~ ~s(phx-hook="MuxUpload")
    assert html =~ ~s(data-lesson-id="l1")
    assert html =~ "type=\"file\""
  end

  test "shows processing status and hides the upload control while in-flight" do
    html = field(%{lesson_id: "l1", status: :processing})
    assert html =~ "Processing…"
    refute html =~ "type=\"file\""
  end

  test "shows ready status" do
    assert field(%{lesson_id: "l1", status: :ready}) =~ "Ready"
  end
end
