# Milestone 0 recap (Foundation) — done, 2026-07-16

Read this alongside `docs/design.md` (the spec) and `CLAUDE.md` (the iron rules) to
pick up work on Milestone 1 with a fresh context. This file exists so you don't have
to re-derive "what actually got built and where it deviated from the plan" from git
log and diffs — read this first, then the code, then the three session plans below
only if you need step-by-step history.

**State: `main` is green.** `mix test` → 74 tests, 0 failures. No open branches, no
uncommitted work. Milestone 0's demo (create a gym → invite a student → student
signs in via magic link → sees the gym's home page) works end to end.

## How this project is planned and built

Established this milestone, not written down elsewhere — worth preserving:

- **Planning happens in a Claude Code chat session** (using the `superpowers`
  `writing-plans` skill), one plan doc per session, saved to
  `docs/superpowers/plans/YYYY-MM-DD-<slug>.md`.
- **Implementation happens in Zed**, via a Claude agent + subagents working from
  that plan doc, in a git worktree under `.claude/worktrees/<branch>/`.
- **Polish** with Tidewave (runtime introspection MCP tools — eval, logs, SQL,
  schema — already wired into both Zed and this environment).
- **Review** with GitHub Copilot.
- Zed's implementation sometimes finds real bugs/gaps the plan missed and fixes them
  beyond the plan's literal scope (see "Deviations" below) — that's expected and
  good; this recap is where those deviations get reconciled back into the shared
  picture.
- Session branches get rebased onto `main` and squash-integrated, then deleted once
  their content is confirmed present on `main` (check via `git diff main...branch`
  being pure historical noise, not stranded content, before deleting).

## What's built

**Two Ash domains exist:** `Matwork.Accounts` (global — `User`, `Token`) and
`Matwork.Gyms` (tenant root + roster). No `Curriculum` or `Media` domain yet — that's
all of Milestone 1.

### `Matwork.Gyms` (`lib/matwork/gyms.ex` + `lib/matwork/gyms/`)

- **`Gym`** (global) — `create_gym/2`, `get_gym_by_id/2`, `get_gym_by_slug/2`. Public
  read (`always()`); create requires any signed-in actor. Creating a gym
  relates the actor as `:owner` and auto-creates their `owner` `Membership`
  (`Gym.Changes.CreateOwnerMembership`).
- **`Membership`** (tenant-scoped on `gym_id`) — `create_owner_membership/2`,
  `remove_membership/1`, `list_memberships/1`, `accept_invite/2`,
  `get_membership_for_user/2` (new this milestone — `get_by: [:user_id]` on the
  existing `:read` action, no new resource action). Read policy is
  `Checks.ActiveMember` — a whole-action check ("does the actor have any active
  membership in this tenant"), not a row filter; this is self-referential by design,
  see the note in `Matwork.Gyms.resolve_current_membership/2`'s moduledoc.
- **`Invite`** (tenant-scoped) — `create_invite/3`, `get_invite_by_token/2`,
  `mark_invite_accepted/1`, `list_invites/1`. Accepting is gated by token possession
  (`Checks.CanMarkInviteAccepted` / the `AcceptInvite` change) — same trust model as
  magic-link sign-in, not a membership check (the invitee has no membership yet).
  `Invite.create`'s policy (`Checks.CanInviteRole`) lets an owner invite anyone, an
  instructor only invite a `:student`.
- **`Matwork.Gyms.resolve_current_membership/2`** — plain function (not a code
  interface), shared by the plug and the `on_mount` hook (see below).

### Web layer

- **Tenant resolution**: `MatworkWeb.Plugs.LoadGym` (controllers) and
  `MatworkWeb.GymLiveAuth` (`on_mount`, LiveViews) both independently resolve
  `:slug` → `Gym` + the actor's `Membership`, rather than trusting
  `AshAuthentication`'s session-propagated tenant across live-navigation — see the
  design note in the session-3 plan for why. `/g/:slug` is wired via a `:gym`
  pipeline in `router.ex`.
- **LiveViews**: `GymNewLive` (`/gyms/new`, create a gym), `GymShowLive` (`/g/:slug`,
  roster + invite form), `InviteAcceptLive` (`/g/:slug/invite/:token`, the
  invite→join critical flow, tested per `CLAUDE.md`'s requirement).
- **`StalwartUI`**: `RosterTable` and `InviteForm` — first two entries in
  `COMPONENTS.md`, plain-assigns only, no resource/domain/route-helper references.
- **Nav bar** (done as an unplanned follow-up session, see
  `docs/superpowers/specs/2026-07-16-nav-role-auth-layout-design.md`): replaced the
  default Phoenix-scaffold header in `Layouts.app/1` with a role/auth-aware one —
  gym name (linking to `/g/:slug`) or "Matwork" as the brand mark, sign-in/sign-out +
  "Create a gym" based on `current_user`/`current_gym` assigns. Marketing home page
  and the AshAuthentication-owned sign-in/sign-out pages were explicitly out of
  scope.
- **Invite email**: `Invite.Changes.SendInviteEmail` fires on `Invite.create`,
  sending via `Invite.Senders.SendInviteEmail` (mirrors the existing magic-link
  sender's pattern). Visible in dev at `/dev/mailbox` (`Swoosh.Adapters.Local`).

### Deploy scaffold (not launched)

`Dockerfile`, `.dockerignore`, `rel/`, `lib/matwork/release.ex` (via
`mix phx.gen.release --docker`), hand-written `fly.toml`, and `docs/deploy.md` with
the manual `fly launch`/`fly deploy` steps. **Nobody has run `fly launch` or
`fly deploy` yet** — this needs your Fly account/CLI auth and is still an open task
whenever you want the app actually hosted.

### Dev environment

`.env` (gitignored) is auto-loaded by `config/runtime.exs` via `Dotenvy` on every
`mix phx.server`/`mix test`/`mix run` in `:dev` — no manual `source` step. See
`.env.example`. Nothing required yet; this is where Mux/Stripe test keys will go in
Milestone 1/2.

## Deviations from the original plans — security fixes found during implementation

The session-3 plan (as I wrote it) did **not** anticipate these; Zed's
implementation found and fixed real authorization gaps. Read the actual code
(`lib/matwork/gyms/checks/roster_visible.ex`, `lib/matwork/accounts/user.ex`), not
the plan doc, for the current behavior:

1. **`Matwork.Gyms.Checks.RosterVisible`** (new file, not in any plan) — a
   `Ash.Policy.FilterCheck` added to `User`'s `:read` policy. The original gap: an
   owner/instructor of *any* gym could read *any* user (roster visibility was
   checked, but not scoped to "the same gym"). This check now requires the actor to
   be an active owner/instructor **in the same gym** the target user is also an
   active member of.
2. **`Matwork.Accounts.User`'s read policy** was tightened to
   `authorize_if expr(id == ^actor(:id))` (read your own record) OR
   `RosterVisible` — replacing a looser earlier version. Covered by
   `test/matwork/accounts/user_test.exs` (new this milestone) and a strengthened
   roster test asserting a student's email is not leaked to non-members.
3. **Gym roster filtered to active memberships** (`eafa536`) — `GymShowLive`'s
   roster listing was crashing/leaking on removed members; now filtered to
   `status: :active` before rendering.

If you're touching `Membership`/`Invite`/`User` policies in Milestone 1 (e.g. for
Curriculum instructor-gating), read these three commits' diffs first — the pattern
(tenant-scoped FilterCheck, self-referential ActiveMember check, token-possession
trust model) is the one to reuse, not reinvent.

## Explicitly deferred (from design.md's Milestone 0 scope or discovered along the way)

- Fly launch/deploy (needs your credentials — scaffold is ready, see above).
- LiveView test for "subscribe → watch" — `CLAUDE.md` requires it, but no
  `Subscription`/`Lesson` resources exist yet (Milestone 1/2).
- No UI for revoking/re-sending an invite, or for `mark_invite_accepted` outside the
  accept flow — design.md doesn't call for it in the POC.
- `InviteForm`'s role options default to `[:instructor, :student]` regardless of
  actor role — an instructor-actor isn't UI-restricted to `[:student]` only (the
  `CanInviteRole` policy already rejects it server-side, so this is a UX gap, not a
  security gap). Worth fixing before Milestone 3's "hand an account to a friendly
  black belt" demo.
- Production mailer adapter (Resend/Postmark) — `config/prod.exs` still needs this
  wired in; not needed until an actual prod deploy happens.
- Nav bar: no footer, no cross-tenant "gyms I belong to" list, no role-specific nav
  shortcuts — see the nav-bar spec doc's explicit scope-out list if any of this
  becomes relevant.

## Full session-by-session detail (only if you need it)

- `docs/superpowers/plans/2026-07-14-milestone-0-session-2-gym-membership-invite.md`
  — Gym/Membership/Invite resources.
- `docs/superpowers/plans/2026-07-15-milestone-0-session-3-tenant-plug-liveviews-deploy-scaffold.md`
  — tenant plug/on_mount, the three LiveViews, deploy scaffold.
- `docs/superpowers/plans/2026-07-16-nav-role-auth-layout.md` +
  `docs/superpowers/specs/2026-07-16-nav-role-auth-layout-design.md` — nav bar
  follow-up.

## What's next

**Milestone 1 — Curriculum + video** (`docs/design.md` §8): `Course` /
`CourseSection` / `Lesson` resources with instructor-gated actions and
publish/archive state transitions, `Video` resource + Mux direct upload from the
lesson form, webhook + Oban processing driving `Video` state, signed playback from
the start, free-preview lessons watchable by any roster member. Demo: instructor
builds a real mini-course with real footage and watches it play back.
