# Nav bar: role/auth-aware layout, removing Phoenix scaffold leftovers

## Problem

`MatworkWeb.Layouts.app/1` (`lib/matwork_web/components/layouts.ex`) still has the
default Phoenix-generator nav header: links to phoenixframework.org, the Phoenix
GitHub repo, hexdocs "Get Started", and a `v{Phoenix version}` badge. It also
declares an unused `current_scope` attr (nothing in the app sets it — dead since
scaffold). None of this reflects Matwork or is useful to a signed-in user.

## Scope

In scope: the header inside `Layouts.app` only, and its three call sites
(`GymShowLive`, `GymNewLive`, `InviteAcceptLive`).

Explicitly out of scope (deferred):
- The `/` home page's marketing content (separate template, doesn't call
  `Layouts.app` — confirmed by reading `home.html.heex`, it renders directly under
  the root layout, not through `Layouts.app`).
- The sign-in/sign-out pages, which use `AshAuthentication.Phoenix.LayoutView`, not
  `Layouts.app`.
- A "powered by Matwork" footer — mentioned by the user as a future direction, not
  built now.
- Any cross-tenant "list all gyms I belong to" feature — no such query exists today
  (`Membership` is tenant-scoped; `Matwork.Gyms` only exposes
  `get_membership_for_user/1` within a given gym's tenant). Building that is separate
  work, not a nav-bar concern.
- Role-specific nav items (e.g. an "Invite" shortcut for owners/instructors). Those
  actions stay inline on the gym page body, as they are today.
- One-click sign-out. The existing two-step `/sign-out` confirm page is unchanged;
  the nav just links to it.

## Design

### `Layouts.app/1` attrs

- `flash` (unchanged, required).
- `current_user` — new, default `nil`. Same struct already assigned by
  `MatworkWeb.LiveUserAuth`'s on_mount hooks in every call site.
- `current_gym` — new, default `nil`. Same struct already assigned by
  `MatworkWeb.GymLiveAuth` on gym-scoped pages (`GymShowLive`, `InviteAcceptLive`).
- Remove `current_scope` (unused).

### Brand mark (left side of header)

- If `current_gym` is present: the gym's name, linking to `/g/#{slug}`.
- Otherwise: the text "Matwork", linking to `/`.
- This is an interim placeholder. The longer-term direction (not built here) is
  letting gyms brand themselves, with a subtle "powered by Matwork" elsewhere (e.g.
  a footer) once a real theme engine and design spec exist.

### Right side of header, by auth state

- Theme toggle: unchanged, always present (not a Phoenix-branding concern).
- Signed out (`current_user` is `nil`): a "Sign in" link to `/sign-in`.
- Signed in: the user's email as plain text, a "Create a gym" link to `/gyms/new`
  (anyone signed in can create a gym today — no restriction to add), and a
  "Sign out" link to the existing `/sign-out` confirmation page (no change to that
  flow, just relocating the entry point into the new nav).

### Call site changes

- `GymShowLive` and `InviteAcceptLive`: pass `current_gym={@current_gym}` in
  addition to existing assigns (both already have `current_gym` on the socket via
  `GymLiveAuth`).
- `GymNewLive`: no `current_gym` to pass (not gym-scoped); brand falls back to
  "Matwork".
- All three: pass `current_user={@current_user}` (already on the socket via
  `LiveUserAuth`).

## Testing

- No existing test asserts on the removed nav markup (grepped `test/` for
  "Website", "GitHub", "Get Started", "navbar", "Layouts.app", "current_scope" —
  no hits).
- Add/extend LiveView tests for `GymShowLive` to assert the nav renders the gym name
  as brand mark and the signed-in-user block (email, "Create a gym", "Sign out")
  when authenticated.
- Add a test for the signed-out case showing "Sign in" and the "Matwork" brand
  mark, using a page that allows anonymous access — `GymShowLive` (which uses
  `live_user_optional`) visited without a session.
