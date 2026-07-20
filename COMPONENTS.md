# StalwartUI Components

Running inventory of the app-agnostic component library under `lib/stalwart_ui/`.
Every entry here depends only on `Phoenix.Component`, Tailwind/daisyUI classes,
and its own JS hooks — never on an app resource, domain, or route helper.

## RosterTable (`StalwartUI.RosterTable.roster_table/1`)

Renders a list of gym memberships as a table with role badges (owner/instructor/student).

**Assigns:** `id` (string, default `"roster-table"`), `memberships` (list of maps/structs
with `:id`, `:role`, `:status`, and a loaded `:user` with `:email`, required).

## InviteForm (`StalwartUI.InviteForm.invite_form/1`)

Email + role form for inviting someone to a gym.

**Assigns:** `form` (`Phoenix.HTML.Form`, required), `roles` (list, default
`[:instructor, :student]`), `id` (string, default `"invite-form"`), `on_change`
(string phx-change event name, default `"validate"`), `on_submit` (string
phx-submit event name, default `"invite"`).

## CurriculumTree (`StalwartUI.CurriculumTree.curriculum_tree/1`)

Renders a course's sections and lessons with author controls (add / rename /
delete / reorder / toggle free-preview), emitting parent-supplied phx event
names.

**Assigns:** `sections` (required) — sorted list of `%{id, title, lessons:
[%{id, title, free_preview, video_status}]}`; plus event-name overrides
`on_add_section`, `on_rename_section`, `on_delete_section`, `on_move_section`,
`on_add_lesson`, `on_rename_lesson`, `on_delete_lesson`, `on_move_lesson`,
`on_toggle_preview`, `on_request_upload` (all default to their obvious event
name; `on_request_upload` defaults to `"request_upload"` and is forwarded to
each lesson's `VideoUploadField`). Move and toggle-preview events
carry `phx-value-id` (and `phx-value-direction`, `"up"`/`"down"`, for move).
Delete events use `Phoenix.LiveView.JS.push(event, value: %{id: ...})`
instead of `phx-value-id` (needed so `data-confirm` can still gate the push —
see the module's inline comment) but arrive with the same `%{"id" => ...}`
shape.

## VideoUploadField (`StalwartUI.VideoUploadField.video_upload_field/1`)

Per-lesson video upload affordance: a hidden file input wired to the `MuxUpload`
JS hook plus a status label. The hook pushes the `on_request_upload` event with
`%{"lesson_id" => ...}` and expects a `%{upload_url: ...}` reply, then streams
the file directly to Mux.

**Assigns:** `lesson_id` (required, string); `status` (atom, default `nil` —
one of `nil | :pending_upload | :processing | :ready | :errored`);
`on_request_upload` (string phx event name, default `"request_upload"`).

_CurriculumTree update:_ lesson maps now include `video_status` (the atoms
above), and `curriculum_tree/1` accepts an `on_request_upload` passthrough
(default `"request_upload"`) forwarded to each lesson's `VideoUploadField`.

**Form submit payload shapes:** the rename-section, rename-lesson, and
add-lesson forms each include a hidden `<input name="_id">` — not `"id"` — to
avoid a Phoenix HEEx compiler warning (`name="id"` collides with the form
element's own `id`). As a result their `phx-submit` payloads are
`%{"_id" => ..., "title" => ...}`, not `%{"id" => ...}`. The add-section form
has no hidden id field and submits `%{"title" => ...}`. Event handlers must
pattern-match on `"_id"` for `rename_section`, `rename_lesson`, and
`add_lesson`.
