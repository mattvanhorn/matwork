# Milestone 1 — Curriculum + video (design spec)

Prepared 2026-07-16. Authoritative parent spec: `docs/design.md` (§4 resources, §6
authorization, §7 UI strategy, §8 build sequence). Prior-milestone context:
`docs/superpowers/journal/2026-07-16-milestone-0-recap.md`. Iron rules: `CLAUDE.md`.

This spec covers **all of Milestone 1**. It is built across three sessions
(Curriculum → Media/Mux → Playback), mirroring how Milestone 0 was split. Only
**Session 1 (Curriculum)** gets a detailed implementation plan immediately; Sessions 2
and 3 are specified here in enough detail to build against, and each gets its own
implementation plan when reached.

**Demo at the end of M1:** an instructor builds a real mini-course (Course → Sections →
Lessons) with actual technique footage uploaded through the lesson builder, and watches
it play back through signed Mux playback. A student sees the published course tree with
free-preview lessons watchable and everything else locked.

---

## 1. Scope and non-goals

**In scope (M1):**

- `Curriculum` domain: `Course`, `CourseSection`, `Lesson` — tenant-scoped, with
  instructor-gated CRUD, course publish/archive state transitions, `free_preview`
  lessons, and positional ordering.
- `Media` domain: `Video` — tenant-scoped, driven by Mux direct upload and Mux
  webhooks.
- `Platform` domain: `WebhookEvent` — global, idempotent webhook ledger (Mux is its
  first consumer; Stripe reuses it in M2).
- `Platform.Mux` behaviour for all Mux API interaction; webhook controller + Oban
  processing; signed playback via `Lesson.request_playback_token`.
- Single-page course-builder LiveView (instructor). Minimal read-only student course
  view with preview playback and locked states.

**Explicitly deferred to M2 or later (not in M1):**

- Any `Subscription`/`Plan`/`Commerce` resources. The active-subscription branch of the
  `request_playback_token` policy is **not** added in M1 — only the `free_preview` and
  instructor/owner branches exist.
- Full student-facing paywall/browse UX, subscribe→watch flow (M2 per `design.md` §8).
- Drag-to-reorder curriculum tree component (`design.md` §7). M1 uses up/down reorder;
  drag-drop is a later polish pass.
- Per-course purchases, seminars, and every other §10 deferred item.

---

## 2. Resource model

All three of `Course`, `CourseSection`, `Lesson`, and `Video` are **tenant-scoped**
(attribute multitenancy on `gym_id`, per `CLAUDE.md`'s iron rule). `WebhookEvent` is
**global**. IDs are `uuid_primary_key :id`, matching every other resource in the
codebase — not the `bigserial` this section originally specified (see the Session-1
implementation plan's Global Constraints for the reconciliation). All resources get
timestamps. Money is not involved in M1, so the integer-cents rule does not apply here.

### 2.1 Curriculum domain (`Matwork.Curriculum`, all tenant-scoped)

```
Course
  gym_id           tenant attribute
  title            string, required
  description      string (text)
  status           atom: draft | published | archived, default :draft
  position         integer

CourseSection
  gym_id           tenant attribute
  course_id        belongs_to Course, required
  title            string, required
  position         integer

Lesson
  gym_id           tenant attribute
  section_id       belongs_to CourseSection, required
  title            string, required
  description      string (text)
  free_preview     boolean, default false
  position         integer
  # video_id (belongs_to Video, nullable) is added in Session 2, NOT Session 1 —
  # the FK cannot exist before the Video table does. request_playback_token is
  # added in Session 3.
```

**Design decisions:**

- **Only `Course` carries `status`.** Sections and lessons have no draft/published
  state (design §4 gives status to `Course` only). Publish/archive is a course-level
  operation; a published course exposes its whole tree to students, gated per-lesson by
  `free_preview` (and, in M2, subscription).
- **`position` is a plain integer**, contiguous within a parent, reordered by dedicated
  `reorder` actions (up/down in the UI). No fractional/gap indexing — YAGNI for the POC.
- Sections belong to a course; lessons belong to a section. Both live in the same
  tenant as their parent (`gym_id` matches).

### 2.2 Media domain (`Matwork.Media`, tenant-scoped) — Session 2

```
Video
  gym_id           tenant attribute
  uploaded_by_id   belongs_to User, required
  title            string
  mux_upload_id    string            # direct-upload handshake id
  mux_asset_id     string, nullable  # set by webhook when the asset exists
  mux_playback_id  string, nullable  # signed-playback id, set by webhook
  status           atom: pending_upload | processing | ready | errored,
                        default :pending_upload
  duration_seconds integer, nullable
```

### 2.3 Platform domain (`Matwork.Platform`, global) — Session 2

```
WebhookEvent (global)
  provider         atom: stripe | mux
  external_id      string
  payload          map (jsonb)
  processed_at     utc_datetime, nullable
  identity: unique on (provider, external_id)   # idempotency key
```

Introduced in M1 for Mux; the same resource carries Stripe events in M2. Verified and
inserted by the webhook controller, processed by an Oban job — never inline.

---

## 3. Authorization

Policies live on the resources (`CLAUDE.md`), never in LiveViews/controllers. Every
tenant-scoped call passes `actor:` and `tenant:`.

### 3.1 Curriculum write gating — `ManagesCurriculum` check

A new `Ash.Policy.SimpleCheck`, `Matwork.Curriculum.Checks.ManagesCurriculum`:
the actor has an **active** `:owner` or `:instructor` membership in the current tenant.
This mirrors the existing M0 pattern (`Matwork.Gyms.Checks.ActiveMember`,
`RosterVisible`) — reuse that shape, do not reinvent. It gates:

- `Course`: `create`, `update`, `publish`, `archive`, `unarchive`.
- `CourseSection`: `create`, `update`, `destroy`, `reorder`.
- `Lesson`: `create`, `update`, `destroy`, `reorder`, and (Session 2/3) the
  video-attach and `request_playback_token` write concerns.

Deny paths that MUST be tested: a `:student` actor, and any non-member actor, are
rejected on every write action above.

### 3.2 Curriculum read gating

- **Course read:** owners/instructors (active membership, any role that manages
  curriculum) see all courses in the tenant; students see `status: :published` only.
  Implement as an `Ash.Policy.FilterCheck` so the list query is filtered, not
  all-or-nothing.
- **Section/Lesson read:** inherit course visibility (a lesson is readable iff its
  course is). Non-members read nothing (tenant isolation already enforced by Ash;
  policies add the intra-tenant role/publish filter).

### 3.3 Playback authorization — Session 3

`Lesson.request_playback_token` authorizes when **any** of:

- the lesson is `free_preview`; **or**
- the actor has an active `:owner`/`:instructor` membership in the tenant.

The active-subscription branch is added in **M2** (no `Subscription` resource exists in
M1). This action is the **only** code path that mints a Mux playback JWT (`CLAUDE.md`
iron rule).

Deny paths that MUST be tested: a `:student` on a non-preview lesson, and a non-member
on any lesson (including preview), are denied a token.

### 3.4 System actor for webhook processing

`Video.mark_ready` / `mark_processing` / `mark_errored` are invoked from the Oban
webhook job, where there is no human actor. Rather than `authorize?: false`, define a
`Matwork.Platform.SystemActor` struct and a **bypass policy** on those actions that
authorizes the system actor only. This keeps authorization on the resource and still
gets flagged in the diff summary per `CLAUDE.md`. (`authorize?: false` remains reserved
for seeds/migrations.)

---

## 4. Session 1 — Curriculum authoring (detailed-plan target)

The instructor-facing course builder. No video yet.

### 4.1 Routes (under the existing `:gym` pipeline, `/g/:slug`)

- `/g/:slug/courses` — instructor course index (list + "New course").
- `/g/:slug/courses/new` — create a course.
- `/g/:slug/courses/:id/edit` — **the single-page course builder**.

### 4.2 Course-builder LiveView

One LiveView renders the whole tree for a course and supports, inline:

- Add / rename / delete sections; reorder sections (up/down).
- Add / rename / delete lessons within a section; reorder lessons (up/down); edit a
  lesson's description; toggle `free_preview`.
- Publish / archive / unarchive the course.

Forms use `AshPhoenix.Form` bound to the named Curriculum actions. The LiveView calls
domain code interfaces only — no raw `Ash` queries (`CLAUDE.md`). All calls pass
`actor: current_user` and `tenant: current_gym.id`, resolved by the existing
`MatworkWeb.GymLiveAuth` `on_mount` hook.

### 4.3 StalwartUI component

**`CurriculumTree`** (`lib/stalwart_ui/curriculum_tree.ex`) — renders sections and
lessons from plain assigns, emitting event names supplied by the parent (same
plain-assigns / no-domain-reference discipline as `RosterTable` and `InviteForm`). Add
its entry to `COMPONENTS.md`.

### 4.4 Session 1 tests

- Policy allow+deny for every Course/Section/Lesson write action (instructor/owner
  allowed; student and non-member denied).
- Tenant isolation: an instructor in gym A cannot read or mutate gym B's course tree.
- Course read filter: a student sees only published courses; instructors see drafts.
- Reorder actions produce the expected contiguous ordering.
- A course-builder LiveView test covering the build flow (create course → add section →
  add lesson → publish).

---

## 5. Session 2 — Media / Mux direct upload

### 5.1 `Platform.Mux` behaviour

All Mux API interaction goes through a thin `Platform.Mux` behaviour backed by `Req`
(there is no first-class Elixir Mux SDK; a `Req`-backed behaviour is the idiomatic fit
for the design's "thin behaviours outside Ash" rule). Callbacks (at least):
`create_direct_upload/1`, `get_upload/1`/`get_asset/1` as needed, and
`sign_playback/2` (Session 3). Mox stubs the behaviour in unit tests; real test-mode
keys are used only in a dedicated integration test.

New env vars (add to `.env.example`): `MUX_TOKEN_ID`, `MUX_TOKEN_SECRET`,
`MUX_SIGNING_KEY_ID`, `MUX_SIGNING_KEY_PRIVATE_KEY`.

### 5.2 Upload flow

1. In the course builder, "Upload video" on a lesson calls
   `Media.create_direct_upload` (actor = instructor), which calls
   `Platform.Mux.create_direct_upload`, stores the returned `mux_upload_id`, creates a
   `Video` in `:pending_upload`, and relates it to the lesson (`lesson.video_id`).
   The FK column `Lesson.video_id` (nullable, belongs_to `Video`) is introduced in this
   session together with the `Video` table.
2. A JS hook (Mux UpChunk) uploads the file bytes **browser → Mux directly**; video
   bytes never touch the server.
3. Mux sends `video.asset.ready` (and `video.upload.asset_created`,
   `video.asset.errored`) to a webhook controller. The controller **verifies the Mux
   signature**, inserts a `WebhookEvent` (idempotent on `provider: :mux` + event id),
   and enqueues an Oban job. It does **not** process inline.
4. The Oban job reads the `WebhookEvent` and invokes `Video.mark_ready` (or
   `mark_errored`) with the `SystemActor`, setting `mux_asset_id`, `mux_playback_id`,
   `duration_seconds`, and `status`.
5. On state change, broadcast over Phoenix PubSub so the open builder LiveView flips the
   lesson from "processing" to "ready" without a refresh.

### 5.3 Session 2 tests

- `Media` actions via Mox against `Platform.Mux` (no live calls).
- Webhook idempotency: a duplicate Mux event id inserts one `WebhookEvent` and processes
  once.
- The Oban job drives `Video.mark_ready` and the video reaches `:ready`.
- Webhook signature verification rejects a bad signature.

---

## 6. Session 3 — Signed playback

### 6.1 `Lesson.request_playback_token`

Mints a short-lived Mux **signed** playback JWT (RS256, signed with
`MUX_SIGNING_KEY_*`) via `Platform.Mux.sign_playback`, gated by the policy in §3.3.
The only JWT-minting path in the system.

### 6.2 StalwartUI components

- **`VideoPlayer`** (`lib/stalwart_ui/video_player.ex`) — wraps the Mux Player web
  component via a JS hook; takes `playback_id` + signed `token` as plain assigns.
- **`LockedLesson`** — the locked-state overlay for non-watchable lessons. (This is the
  precursor to M2's paywall gate; keep it app-agnostic.)

Add both to `COMPONENTS.md`.

### 6.3 Student read-only course view

Route `/g/:slug/courses/:id` (read-only): renders the published course tree. Free-preview
lessons render the `VideoPlayer` (the LiveView calls `request_playback_token`, which
succeeds); every other lesson renders `LockedLesson`. Instructors viewing their own
course can watch any lesson.

### 6.4 Session 3 tests

- `request_playback_token` allow paths (free_preview for any roster member; any lesson
  for instructor/owner) and deny paths (student on non-preview; non-member on anything).
- The JWT is minted only through this action (no other call site).
- A LiveView test for the instructor build → upload (Mux mocked) → watch loop, and the
  student preview-vs-locked view.

---

## 7. Component inventory delta (`COMPONENTS.md`)

New `StalwartUI` entries by end of M1: `CurriculumTree` (Session 1), `VideoPlayer` and
`LockedLesson` (Session 3). All plain-assigns, no resource/domain/route-helper
references.

## 8. Migrations & codegen

After each resource change, run `mix ash.codegen <descriptive_name>`; never hand-write
migrations for Ash-managed tables (`CLAUDE.md`). Before every commit: `mix format`,
`mix credo --strict`, `mix test` — all green.

## 9. Open operational prerequisites (not code)

- A Mux account with signed-playback enabled and a signing key pair; keys go in `.env`
  (dev) and Fly secrets (when deployed).
- Real technique footage for the end-of-M1 demo.
- These block the Session-2/3 *demo*, not Session-1 development.
