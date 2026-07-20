defmodule StalwartUI.CurriculumTree do
  @moduledoc """
  Renders a course's sections and lessons with author controls (add / rename /
  delete / reorder / toggle-preview). Emits parent-supplied event names; takes
  plain assigns only — no resource, domain, or route-helper references, per the
  StalwartUI extraction discipline (see COMPONENTS.md).
  """
  use Phoenix.Component

  import StalwartUI.VideoUploadField

  alias Phoenix.LiveView.JS

  # `data-confirm` on the delete buttons below is not a phoenix_live_view feature —
  # phoenix_html.js's global click listener intercepts the click first (it's imported
  # before phoenix_live_view in app.js), reads `data-confirm`, and on cancel calls
  # stopImmediatePropagation() before LiveView's own click handler ever sees the event.
  # This correctly gates the phx-click push even though nothing in phoenix_live_view.js
  # itself knows about `data-confirm` — don't "fix" this by removing it.

  attr :sections, :list,
    required: true,
    doc:
      "sorted list of %{id, title, lessons: [%{id, title, free_preview, video_status}]} — lessons pre-sorted"

  attr :on_add_section, :string, default: "add_section"
  attr :on_rename_section, :string, default: "rename_section"
  attr :on_delete_section, :string, default: "delete_section"
  attr :on_move_section, :string, default: "move_section"
  attr :on_add_lesson, :string, default: "add_lesson"
  attr :on_rename_lesson, :string, default: "rename_lesson"
  attr :on_delete_lesson, :string, default: "delete_lesson"
  attr :on_move_lesson, :string, default: "move_lesson"
  attr :on_toggle_preview, :string, default: "toggle_preview"
  attr :on_request_upload, :string, default: "request_upload"

  def curriculum_tree(assigns) do
    ~H"""
    <div id="curriculum-tree" class="space-y-4">
      <section :for={section <- @sections} id={"section-#{section.id}"} class="rounded border p-3">
        <div class="flex items-center gap-2">
          <form phx-submit={@on_rename_section} class="flex items-center gap-1">
            <input type="hidden" name="_id" value={section.id} />
            <input
              type="text"
              name="title"
              value={section.title}
              class="input input-sm input-bordered"
            />
            <button type="submit" class="btn btn-sm">Save</button>
          </form>
          <button
            type="button"
            phx-click={@on_move_section}
            phx-value-id={section.id}
            phx-value-direction="up"
            aria-label="Move section up"
            class="btn btn-xs"
          >↑</button>
          <button
            type="button"
            phx-click={@on_move_section}
            phx-value-id={section.id}
            phx-value-direction="down"
            aria-label="Move section down"
            class="btn btn-xs"
          >↓</button>
          <button
            type="button"
            phx-click={JS.push(@on_delete_section, value: %{id: section.id})}
            data-confirm="Delete this section and its lessons?"
            class="btn btn-xs btn-error"
          >Delete</button>
        </div>

        <ul class="mt-2 space-y-1">
          <li
            :for={lesson <- section.lessons}
            id={"lesson-#{lesson.id}"}
            class="flex items-center gap-2"
          >
            <form phx-submit={@on_rename_lesson} class="flex items-center gap-1">
              <input type="hidden" name="_id" value={lesson.id} />
              <input
                type="text"
                name="title"
                value={lesson.title}
                class="input input-xs input-bordered"
              />
              <button type="submit" class="btn btn-xs">Save</button>
            </form>
            <span :if={lesson.free_preview} class="badge badge-success badge-sm">Preview</span>
            <.video_upload_field
              lesson_id={lesson.id}
              status={lesson.video_status}
              on_request_upload={@on_request_upload}
            />
            <button
              type="button"
              phx-click={@on_toggle_preview}
              phx-value-id={lesson.id}
              class="btn btn-xs"
            >Toggle preview</button>
            <button
              type="button"
              phx-click={@on_move_lesson}
              phx-value-id={lesson.id}
              phx-value-direction="up"
              aria-label="Move lesson up"
              class="btn btn-xs"
            >↑</button>
            <button
              type="button"
              phx-click={@on_move_lesson}
              phx-value-id={lesson.id}
              phx-value-direction="down"
              aria-label="Move lesson down"
              class="btn btn-xs"
            >↓</button>
            <button
              type="button"
              phx-click={JS.push(@on_delete_lesson, value: %{id: lesson.id})}
              data-confirm="Delete this lesson?"
              class="btn btn-xs btn-error"
            >Delete</button>
          </li>
        </ul>

        <form phx-submit={@on_add_lesson} class="mt-2 flex items-center gap-1">
          <input type="hidden" name="_id" value={section.id} />
          <input
            type="text"
            name="title"
            placeholder="New lesson title"
            class="input input-xs input-bordered"
          />
          <button type="submit" class="btn btn-xs btn-primary">Add lesson</button>
        </form>
      </section>

      <p :if={@sections == []} class="text-sm opacity-70">No sections yet.</p>

      <form phx-submit={@on_add_section} class="flex items-center gap-1">
        <input
          type="text"
          name="title"
          placeholder="New section title"
          class="input input-sm input-bordered"
        />
        <button type="submit" class="btn btn-sm btn-primary">Add section</button>
      </form>
    </div>
    """
  end
end
