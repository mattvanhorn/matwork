defmodule StalwartUI.VideoUploadField do
  @moduledoc """
  Per-lesson video upload affordance: a file input wired to the `MuxUpload`
  JS hook, plus a status label. Plain assigns only — no resource/domain/route
  references (see COMPONENTS.md). The hook pushes `@on_request_upload` to the
  parent LiveView with `%{"lesson_id" => ...}` and expects a `%{upload_url}`
  reply, then streams the file straight to Mux.
  """
  use Phoenix.Component

  attr :lesson_id, :string, required: true

  attr :status, :atom,
    default: nil,
    doc: "nil | :pending_upload | :processing | :ready | :errored"

  attr :on_request_upload, :string, default: "request_upload"

  def video_upload_field(assigns) do
    ~H"""
    <div
      id={"upload-#{@lesson_id}"}
      phx-hook="MuxUpload"
      data-lesson-id={@lesson_id}
      data-event={@on_request_upload}
      class="flex items-center gap-2"
    >
      <span class="text-xs opacity-70">{status_label(@status)}</span>
      <label :if={@status in [nil, :errored]} class="btn btn-xs">
        Upload video <input type="file" accept="video/*" class="hidden" />
      </label>
    </div>
    """
  end

  defp status_label(nil), do: "No video"
  defp status_label(:pending_upload), do: "Uploading…"
  defp status_label(:processing), do: "Processing…"
  defp status_label(:ready), do: "Ready"
  defp status_label(:errored), do: "Upload failed"
end
