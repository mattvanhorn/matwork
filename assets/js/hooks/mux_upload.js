import * as UpChunk from "@mux/upchunk"

// Streams the selected file straight to Mux. Asks the server (via the event
// named in data-event) for a one-time upload URL, then uploads the bytes
// directly — they never touch the Phoenix server. The server-side Video state
// is driven by Mux webhooks, not by this hook.
export const MuxUpload = {
  mounted() {
    const input = this.el.querySelector("input[type=file]")
    if (!input) return

    input.addEventListener("change", (e) => {
      const file = e.target.files && e.target.files[0]
      if (!file) return

      const event = this.el.dataset.event
      const lessonId = this.el.dataset.lessonId

      this.pushEvent(event, {lesson_id: lessonId}, (reply) => {
        if (!reply || !reply.upload_url) return

        const upload = UpChunk.createUpload({endpoint: reply.upload_url, file})
        upload.on("error", () => this.pushEvent("upload_failed", {lesson_id: lessonId}))
        upload.on("success", () => this.pushEvent("upload_finished", {lesson_id: lessonId}))
      })
    })
  },
}
