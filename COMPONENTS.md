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
[%{id, title, free_preview}]}`; plus event-name overrides `on_add_section`,
`on_rename_section`, `on_delete_section`, `on_move_section`, `on_add_lesson`,
`on_rename_lesson`, `on_delete_lesson`, `on_move_lesson`, `on_toggle_preview`
(all default to their obvious event name). Move events carry `phx-value-id`
and `phx-value-direction` (`"up"`/`"down"`).
