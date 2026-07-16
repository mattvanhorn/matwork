# Milestone 0, Session 3: Tenant Resolution, Gym LiveViews, and Deploy Scaffold Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Gyms domain (built in session 2) into the web layer — a tenant-resolution plug + `on_mount` hook that resolve `/g/:slug` to a `Gym` and the actor's `Membership`, three LiveViews (create a gym, view a gym's roster and invite members, accept an invite), the first two `StalwartUI` components, and a scaffolded (not launched) Fly.io deploy pipeline. This closes out `docs/design.md`'s Milestone 0 demo: "create a gym, invite a student by email, student signs in via magic link and sees the gym's empty home page."

**Architecture:** A named Phoenix pipeline (`:gym`) wrapping a plug that resolves `:slug` → `Gym`, sets the Ash tenant on the conn, and assigns `:current_gym`/`:current_membership`. A parallel `on_mount` hook does the same for the LiveView socket (plug and hook independently re-resolve rather than one feeding the other — conn assigns don't cross into LiveView sockets, only `Ash.PlugHelpers`-tracked tenant/context do, and relying on that propagation surviving live-navigation between different gym slugs is not something to bet a POC's correctness on). Every LiveView calls `Matwork.Gyms` code interfaces — including forms, via `AshPhoenix.Form` and the domain's generated `form_to_*` functions — never raw `Ash` calls. Fly deployment is scaffolded (Dockerfile, `fly.toml`, documented manual steps) but not launched, since that requires your Fly account credentials.

**Tech Stack:** Phoenix 1.8 LiveView, `AshPhoenix.Form`, `AshAuthentication.Phoenix` (`ash_authentication_live_session`, `LiveUserAuth`), Swoosh (invite email, mirroring the existing magic-link sender), `mix phx.gen.release --docker` for the production Dockerfile.

## Global Constraints

- Tenant plumbing: gyms live under `/g/:gym_slug/...`. A plug (controllers) and an `on_mount` hook (LiveViews) resolve the slug to a `Gym`, call `Ash.PlugHelpers.set_tenant/2`, and assign `current_gym` and the actor's `Membership` (nil if none). (`docs/design.md` §3)
- Code interface calls from LiveViews pass `tenant: gym.id` and `actor: current_user`. (`docs/design.md` §3, `CLAUDE.md`)
- LiveViews call domain code interfaces; they do not build raw queries. Authorization lives in resource policies, never in LiveViews or controllers. (`CLAUDE.md`)
- Reusable UI lives under `lib/stalwart_ui/`, depending only on `Phoenix.Component`, Tailwind, and its own JS hooks — never on resources, domains, or route helpers. Update `COMPONENTS.md` whenever a `StalwartUI` component is created or materially changed. (`CLAUDE.md`, `docs/design.md` §7)
- No `authorize?: false` outside seeds, migrations, and system-actor webhook jobs — flag it in the diff summary when used. (`CLAUDE.md`) — this plan introduces none; every Ash call below passes a real `actor:`.
- After changing resources, run `mix ash.codegen <descriptive_name>`. (`CLAUDE.md`) — one resource-level addition this session (a new domain code interface, no attribute changes), so codegen is expected to report "no changes" for the database and only touch the generated interface; run it anyway per the rule.
- Before every commit: `mix format`, `mix credo --strict`, `mix test` — all green. (`CLAUDE.md`)
- Small commits, one concern each, imperative subject lines. (`CLAUDE.md`)
- LiveView tests for the critical flows: invite → join, subscribe → watch. (`docs/design.md` §9) — this session implements and tests invite → join; subscribe → watch is Milestone 2.
- `mix usage_rules.docs <Module>` / `mix usage_rules.search_docs <query> -p ash -p phoenix -p phoenix_live_view` are available if an implementer needs to double check an API call beyond what's specified below.

## Scope note (confirmed with the human before writing this plan)

`docs/design.md`'s Milestone 0 bundles "deploy pipeline to Fly.io" in with the plug/routing/LiveView work. Actually running `fly launch` / `fly deploy` requires your Fly account and CLI authentication, which this plan can't execute. Per your direction, this plan **scaffolds** the deploy artifacts (Dockerfile via `mix phx.gen.release --docker`, a hand-written `fly.toml`, and a `docs/deploy.md` with the manual steps) as Task 6, but does not attempt to launch or deploy anything.

## Design notes worth recording

1. **Why the plug and the `on_mount` hook don't share state via `Ash.PlugHelpers`.** `AshAuthentication.Phoenix.LiveSession.generate_session/3` (the session-building function `ash_authentication_live_session` wires up) does capture `Ash.PlugHelpers.get_tenant(conn)` into the LiveView session's `"tenant"` key automatically, and AshAuthentication's own `on_mount(:default, ...)` assigns it to `socket.assigns.current_tenant`. It would be possible to have the `on_mount` hook just trust `current_tenant` instead of re-resolving from `params["slug"]`. This plan does **not** do that: that propagation is computed once per dead-render (the initial HTTP request) and its behavior under live-navigation between two *different* gym slugs inside the same connected session is a subtlety not worth betting correctness on for a POC. Both the plug and the `on_mount` hook independently resolve `slug → {gym, membership}` via one shared domain-level helper (`Matwork.Gyms.resolve_current_membership/2`), so there is no logic duplicated, just the (cheap) resolution call itself running twice per request — once in the plug (which also gets the benefit of a clean 404 for a bad slug before any LiveView socket is even opened), once in the `on_mount` hook (which populates the actual socket assigns, since conn assigns never cross into LiveView sockets).
2. **`Matwork.Gyms.get_membership_for_user/2`** is a new code interface, not a new action — it uses the existing `Membership` `:read` action with `get_by: [:user_id]`, since `unique_user_per_gym` is already a tenant-scoped identity on `[:user_id]`. This is the "prefer the primary read action + `get_by` for get-style lookups" pattern from the Ash usage rules; no new resource action needed.
3. **`AshPhoenix.Form` requires the `AshPhoenix` extension on the domain** to generate `form_to_*` functions. This plan adds `extensions: [AshPhoenix]` to `Matwork.Gyms`.

## File Structure

```
lib/matwork_web/plugs/load_gym.ex               # tenant-resolution plug
lib/matwork_web/gym_live_auth.ex                 # on_mount hook, mirrors LoadGym
lib/matwork/gyms.ex                               # +extensions:[AshPhoenix], +get_membership_for_user, +resolve_current_membership/2
lib/matwork_web/router.ex                          # +:gym pipeline, +/g/:slug scope, +/gyms/new route
test/support/conn_case.ex                          # +sign_in/2 test helper
test/matwork_web/plugs/load_gym_test.exs

lib/stalwart_ui/roster_table.ex
lib/stalwart_ui/invite_form.ex
COMPONENTS.md
test/stalwart_ui/roster_table_test.exs
test/stalwart_ui/invite_form_test.exs

lib/matwork_web/live/gym_new_live.ex
test/matwork_web/live/gym_new_live_test.exs

lib/matwork/gyms/invite/senders/send_invite_email.ex
lib/matwork/gyms/invite/changes/send_invite_email.ex
lib/matwork/gyms/invite.ex                         # +SendInviteEmail change on :create
lib/matwork_web/live/gym_show_live.ex
test/matwork_web/live/gym_show_live_test.exs

lib/matwork_web/live/invite_accept_live.ex
test/matwork_web/live/invite_accept_live_test.exs

Dockerfile                                          # generated by mix phx.gen.release --docker
.dockerignore                                       # generated
rel/overlays/bin/*                                  # generated
lib/matwork/release.ex                              # generated
fly.toml
docs/deploy.md
```

---

### Task 1: Tenant resolution — plug, `on_mount` hook, router wiring, test sign-in helper

**Files:**
- Modify: `lib/matwork/gyms.ex`
- Create: `lib/matwork_web/plugs/load_gym.ex`
- Create: `lib/matwork_web/gym_live_auth.ex`
- Modify: `lib/matwork_web/router.ex`
- Modify: `test/support/conn_case.ex`
- Test: `test/matwork_web/plugs/load_gym_test.exs`

**Interfaces:**
- Produces: `Matwork.Gyms.get_membership_for_user(user_id, opts)` / `!` — a get-style code interface for "this user's own membership in the current tenant."
- Produces: `Matwork.Gyms.resolve_current_membership(user_or_nil, gym)` — plain function (not a code interface), returns the user's active `Membership` in `gym`, or `nil`. Shared by the plug and the `on_mount` hook.
- Produces: `MatworkWeb.Plugs.LoadGym` — assigns `:current_gym`/`:current_membership` on `conn`, 404s on a bad slug.
- Produces: `MatworkWeb.GymLiveAuth` `on_mount(:default, params, session, socket)` — assigns `:current_gym`/`:current_membership` on the socket. Must be declared *after* `{MatworkWeb.LiveUserAuth, :live_user_optional}` (or `:live_user_required`) in a LiveView's own `on_mount` list, since it reads `socket.assigns[:current_user]`.
- Produces: `MatworkWeb.ConnCase.sign_in(conn, user)` — test helper; later tasks' LiveView tests depend on this.
- Consumes: `Matwork.Gyms.get_gym_by_slug/2` (session 2).

- [ ] **Step 1: Add the domain helper and code interface**

Modify `lib/matwork/gyms.ex`, changing:

```elixir
defmodule Matwork.Gyms do
  @moduledoc "The Gyms domain: gym management and tenant roots."
  use Ash.Domain,
    otp_app: :matwork

  resources do
    resource Matwork.Gyms.Gym do
      define :create_gym, action: :create, args: [:name, :slug]
      define :get_gym_by_id, action: :read, get_by: [:id]
      define :get_gym_by_slug, action: :read, get_by: [:slug]
    end

    resource Matwork.Gyms.Membership do
      define :create_owner_membership, action: :create_owner, args: [:user_id]
      define :remove_membership, action: :remove
      define :list_memberships, action: :read
      define :accept_invite, action: :accept_invite, args: [:token]
    end

    resource Matwork.Gyms.Invite do
      define :create_invite, action: :create, args: [:email, :role]
      define :get_invite_by_token, action: :get_by_token, args: [:token]
      define :mark_invite_accepted, action: :mark_accepted
      define :list_invites, action: :read
    end
  end
end
```

to:

```elixir
defmodule Matwork.Gyms do
  @moduledoc "The Gyms domain: gym management and tenant roots."
  use Ash.Domain,
    otp_app: :matwork,
    extensions: [AshPhoenix]

  resources do
    resource Matwork.Gyms.Gym do
      define :create_gym, action: :create, args: [:name, :slug]
      define :get_gym_by_id, action: :read, get_by: [:id]
      define :get_gym_by_slug, action: :read, get_by: [:slug]
    end

    resource Matwork.Gyms.Membership do
      define :create_owner_membership, action: :create_owner, args: [:user_id]
      define :remove_membership, action: :remove
      define :list_memberships, action: :read
      define :accept_invite, action: :accept_invite, args: [:token]
      define :get_membership_for_user, action: :read, get_by: [:user_id]
    end

    resource Matwork.Gyms.Invite do
      define :create_invite, action: :create, args: [:email, :role]
      define :get_invite_by_token, action: :get_by_token, args: [:token]
      define :mark_invite_accepted, action: :mark_accepted
      define :list_invites, action: :read
    end
  end

  @doc """
  The given user's active Membership in `gym`, or `nil` if they have none
  (including if `user` is `nil`, i.e. not signed in).
  """
  def resolve_current_membership(nil, _gym), do: nil

  def resolve_current_membership(user, gym) do
    case get_membership_for_user(user.id, actor: user, tenant: gym.id) do
      {:ok, membership} -> membership
      {:error, _not_found} -> nil
    end
  end
end
```

- [ ] **Step 2: Run codegen (no schema change expected, but required by workflow rules)**

```bash
mix ash.codegen add_get_membership_for_user_interface
```

Expected: this only adds a domain code interface, not an attribute — the command should report no pending migrations. If it generates an empty migration file, delete it; if it reports nothing to do, that's correct.

- [ ] **Step 3: Write the plug**

Create `lib/matwork_web/plugs/load_gym.ex`:

```elixir
defmodule MatworkWeb.Plugs.LoadGym do
  @moduledoc """
  Resolves the `:slug` path param to a `Gym`, sets it as the Ash tenant on
  the conn, and assigns `:current_gym` and `:current_membership` (`nil` if
  the signed-in user, if any, has no active membership in this gym).
  Responds 404 if the slug does not resolve to a gym.
  """
  import Plug.Conn

  alias Matwork.Gyms

  def init(opts), do: opts

  def call(conn, _opts) do
    actor = conn.assigns[:current_user]

    case Gyms.get_gym_by_slug(conn.params["slug"], actor: actor) do
      {:ok, gym} ->
        conn
        |> Ash.PlugHelpers.set_tenant(gym.id)
        |> assign(:current_gym, gym)
        |> assign(:current_membership, Gyms.resolve_current_membership(actor, gym))

      {:error, _not_found} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "Gym not found")
        |> halt()
    end
  end
end
```

- [ ] **Step 4: Write the `on_mount` hook**

Create `lib/matwork_web/gym_live_auth.ex`:

```elixir
defmodule MatworkWeb.GymLiveAuth do
  @moduledoc """
  `on_mount` hook for LiveViews scoped under `/g/:slug`. Resolves the
  `:slug` path param to a `Gym` and the actor's `Membership`, assigning
  `:current_gym`/`:current_membership` on the socket.

  Must be declared *after* `{MatworkWeb.LiveUserAuth, :live_user_optional}`
  (or `:live_user_required`) in a LiveView's `on_mount` list, since it
  reads `socket.assigns[:current_user]`.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  use MatworkWeb, :verified_routes

  alias Matwork.Gyms

  def on_mount(:default, %{"slug" => slug}, _session, socket) do
    actor = socket.assigns[:current_user]

    case Gyms.get_gym_by_slug(slug, actor: actor) do
      {:ok, gym} ->
        {:cont,
         socket
         |> assign(:current_gym, gym)
         |> assign(:current_membership, Gyms.resolve_current_membership(actor, gym))}

      {:error, _not_found} ->
        {:halt,
         socket
         |> put_flash(:error, "Gym not found")
         |> redirect(to: ~p"/")}
    end
  end
end
```

- [ ] **Step 5: Wire the plug into the router**

Modify `lib/matwork_web/router.ex`, changing:

```elixir
  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end
```

to:

```elixir
  pipeline :gym do
    plug MatworkWeb.Plugs.LoadGym
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end
```

and adding a new scope right after the existing `ash_authentication_live_session :authenticated_routes` scope block:

```elixir
  scope "/g/:slug", MatworkWeb do
    pipe_through [:browser, :gym]

    # LiveViews are added inside this scope in later tasks (Task 3 for
    # /gyms/new — a sibling scope, not gym-scoped — and Tasks 4/5 for the
    # gym home page and accept-invite page here).
  end
```

- [ ] **Step 6: Add the test sign-in helper**

Modify `test/support/conn_case.ex`, changing:

```elixir
  using do
    quote do
      # The default endpoint for testing
      @endpoint MatworkWeb.Endpoint

      use MatworkWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MatworkWeb.ConnCase
    end
  end

  setup tags do
    Matwork.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
```

to:

```elixir
  using do
    quote do
      # The default endpoint for testing
      @endpoint MatworkWeb.Endpoint

      use MatworkWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MatworkWeb.ConnCase
    end
  end

  setup tags do
    Matwork.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Signs `user` into `conn`'s session the same way a real magic-link
  sign-in would, for use in controller and LiveView tests.
  """
  def sign_in(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    user_with_token = %{user | __metadata__: Map.put(user.__metadata__, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(user_with_token)
  end
end
```

- [ ] **Step 7: Write the failing plug tests**

Create `test/matwork_web/plugs/load_gym_test.exs`:

```elixir
defmodule MatworkWeb.Plugs.LoadGymTest do
  use MatworkWeb.ConnCase, async: true

  import Matwork.Generator

  alias MatworkWeb.Plugs.LoadGym

  describe "call/2" do
    test "assigns current_gym and current_membership for the gym's owner", %{conn: conn} do
      owner = generate(user())
      gym = Matwork.Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      conn =
        conn
        |> sign_in(owner)
        |> Map.put(:params, %{"slug" => "rickson-academy"})
        |> LoadGym.call([])

      assert conn.assigns.current_gym.id == gym.id
      assert conn.assigns.current_membership.role == :owner
      assert Ash.PlugHelpers.get_tenant(conn) == gym.id
    end

    test "assigns current_membership nil for a signed-in stranger", %{conn: conn} do
      owner = generate(user())
      Matwork.Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)
      stranger = generate(user())

      conn =
        conn
        |> sign_in(stranger)
        |> Map.put(:params, %{"slug" => "rickson-academy"})
        |> LoadGym.call([])

      refute conn.halted
      assert conn.assigns.current_gym.slug == Ash.CiString.new("rickson-academy")
      assert conn.assigns.current_membership == nil
    end

    test "assigns current_gym for an unauthenticated visitor (public read)", %{conn: conn} do
      owner = generate(user())
      Matwork.Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      conn =
        conn
        |> Map.put(:params, %{"slug" => "rickson-academy"})
        |> LoadGym.call([])

      refute conn.halted
      assert conn.assigns.current_gym.slug == Ash.CiString.new("rickson-academy")
      assert conn.assigns.current_membership == nil
    end

    test "404s for a nonexistent slug", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"slug" => "does-not-exist"})
        |> LoadGym.call([])

      assert conn.halted
      assert conn.status == 404
    end
  end
end
```

- [ ] **Step 8: Run the tests and verify they pass**

```bash
mix test test/matwork_web/plugs/load_gym_test.exs
```

Expected: `4 tests, 0 failures`.

- [ ] **Step 9: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add lib/matwork/gyms.ex lib/matwork_web/plugs/load_gym.ex lib/matwork_web/gym_live_auth.ex \
  lib/matwork_web/router.ex test/support/conn_case.ex test/matwork_web/plugs/load_gym_test.exs \
  priv/repo/migrations/ priv/resource_snapshots/
git commit -m "Add tenant-resolution plug, on_mount hook, and /g/:slug scope"
```

---

### Task 2: `StalwartUI` roster table and invite form components

**Files:**
- Create: `lib/stalwart_ui/roster_table.ex`
- Create: `lib/stalwart_ui/invite_form.ex`
- Create: `COMPONENTS.md`
- Test: `test/stalwart_ui/roster_table_test.exs`
- Test: `test/stalwart_ui/invite_form_test.exs`

**Interfaces:**
- Produces: `StalwartUI.RosterTable.roster_table/1` — takes `memberships` (list of maps/structs each with `:id`, `:role`, and a loaded `:user` with `:email`) and renders a table with role badges. Plain assigns only; no `Matwork.Gyms` reference.
- Produces: `StalwartUI.InviteForm.invite_form/1` — takes a `Phoenix.HTML.Form` (`@form`) plus `:roles`, renders an email + role invite form. Plain assigns only.
- Consumes: nothing (StalwartUI components never depend on app resources per the iron rule) — this task is independent of Task 1.

- [ ] **Step 1: Write the roster table component**

Create `lib/stalwart_ui/roster_table.ex`:

```elixir
defmodule StalwartUI.RosterTable do
  @moduledoc """
  Renders a gym's roster as a table with role badges.

  Takes plain assigns only — no resource, domain, or route-helper
  references, per the StalwartUI extraction discipline (see COMPONENTS.md).
  """
  use Phoenix.Component

  attr :id, :string, default: "roster-table"

  attr :memberships, :list,
    required: true,
    doc: "list of maps/structs with :id, :role, :status, and a loaded :user with :email"

  def roster_table(assigns) do
    ~H"""
    <table id={@id} class="table">
      <thead>
        <tr>
          <th>Member</th>
          <th>Role</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={membership <- @memberships} id={"#{@id}-row-#{membership.id}"}>
          <td>{to_string(membership.user.email)}</td>
          <td><span class={role_badge_class(membership.role)}>{membership.role}</span></td>
          <td>{membership.status}</td>
        </tr>
      </tbody>
    </table>
    <p :if={@memberships == []} class="text-sm opacity-70">No members yet.</p>
    """
  end

  defp role_badge_class(:owner), do: "badge badge-primary"
  defp role_badge_class(:instructor), do: "badge badge-secondary"
  defp role_badge_class(:student), do: "badge badge-ghost"
end
```

- [ ] **Step 2: Write the invite form component**

Create `lib/stalwart_ui/invite_form.ex`:

```elixir
defmodule StalwartUI.InviteForm do
  @moduledoc """
  A form for inviting someone to a gym by email and role.

  Takes a `Phoenix.HTML.Form` and role options as plain assigns — no
  resource, domain, or route-helper references, per the StalwartUI
  extraction discipline (see COMPONENTS.md).
  """
  use Phoenix.Component

  attr :form, Phoenix.HTML.Form, required: true
  attr :roles, :list, default: [:instructor, :student]
  attr :id, :string, default: "invite-form"
  attr :on_change, :string, default: "validate"
  attr :on_submit, :string, default: "invite"

  def invite_form(assigns) do
    ~H"""
    <.form for={@form} id={@id} phx-change={@on_change} phx-submit={@on_submit}>
      <input
        type="email"
        name={@form[:email].name}
        id={@form[:email].id}
        value={@form[:email].value}
        placeholder="Email address"
        class="input"
      />
      <select name={@form[:role].name} id={@form[:role].id} class="select">
        <option :for={role <- @roles} value={role} selected={to_string(@form[:role].value) == to_string(role)}>
          {role}
        </option>
      </select>
      <button type="submit" class="btn btn-primary">Send invite</button>
    </.form>
    """
  end
end
```

- [ ] **Step 3: Create the components catalog**

Create `COMPONENTS.md`:

```markdown
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
```

- [ ] **Step 4: Write the failing component tests**

Create `test/stalwart_ui/roster_table_test.exs`:

```elixir
defmodule StalwartUI.RosterTableTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.RosterTable

  test "renders a row per membership with a role badge" do
    memberships = [
      %{id: "m1", role: :owner, status: :active, user: %{email: "owner@example.com"}},
      %{id: "m2", role: :student, status: :active, user: %{email: "student@example.com"}}
    ]

    html = render_component(&roster_table/1, memberships: memberships)

    assert html =~ "owner@example.com"
    assert html =~ "student@example.com"
    assert html =~ "badge-primary"
    assert html =~ "badge-ghost"
  end

  test "renders an empty state with no memberships" do
    html = render_component(&roster_table/1, memberships: [])

    assert html =~ "No members yet."
  end
end
```

Create `test/stalwart_ui/invite_form_test.exs`:

```elixir
defmodule StalwartUI.InviteFormTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.InviteForm

  test "renders email and role inputs" do
    form = Phoenix.Component.to_form(%{"email" => "", "role" => "student"}, as: :form)

    html = render_component(&invite_form/1, form: form)

    assert html =~ ~s(type="email")
    assert html =~ "instructor"
    assert html =~ "student"
    assert html =~ "Send invite"
  end
end
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
mix test test/stalwart_ui/
```

Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/stalwart_ui/ COMPONENTS.md test/stalwart_ui/
git commit -m "Add StalwartUI RosterTable and InviteForm components"
```

---

### Task 3: Gym creation LiveView

**Files:**
- Create: `lib/matwork_web/live/gym_new_live.ex`
- Modify: `lib/matwork_web/router.ex`
- Test: `test/matwork_web/live/gym_new_live_test.exs`

**Interfaces:**
- Consumes: `Matwork.Gyms.form_to_create_gym/1` (generated by Task 1's `AshPhoenix` extension), `MatworkWeb.LiveUserAuth` (session 1), `MatworkWeb.ConnCase.sign_in/2` (Task 1).
- Produces: route `/gyms/new` → redirects to `/g/:slug` on success.

- [ ] **Step 1: Write the LiveView**

Create `lib/matwork_web/live/gym_new_live.ex`:

```elixir
defmodule MatworkWeb.GymNewLive do
  use MatworkWeb, :live_view

  alias Matwork.Gyms

  on_mount {MatworkWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    form = Gyms.form_to_create_gym(actor: socket.assigns.current_user) |> to_form()
    {:ok, assign(socket, :form, form)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, gym} ->
        {:noreply, push_navigate(socket, to: ~p"/g/#{gym.slug}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Create a gym</.header>
      <.form for={@form} id="gym-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Gym name" />
        <.input field={@form[:slug]} type="text" label="URL slug" />
        <.button variant="primary">Create gym</.button>
      </.form>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 2: Add the route**

Modify `lib/matwork_web/router.ex`, changing:

```elixir
  scope "/", MatworkWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {MatworkWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {MatworkWeb.LiveUserAuth, :live_no_user}
    end
  end
```

to:

```elixir
  scope "/", MatworkWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {MatworkWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {MatworkWeb.LiveUserAuth, :live_no_user}

      live "/gyms/new", GymNewLive
    end
  end
```

- [ ] **Step 3: Write the failing test**

Create `test/matwork_web/live/gym_new_live_test.exs`:

```elixir
defmodule MatworkWeb.GymNewLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  describe "mount" do
    test "requires a signed-in user", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/gyms/new")
    end
  end

  describe "save" do
    test "creates a gym and navigates to its page", %{conn: conn} do
      owner = generate(user())
      conn = sign_in(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/gyms/new")

      {:ok, _view, _html} =
        view
        |> form("#gym-form", form: %{name: "Rickson's Academy", slug: "rickson-academy"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/g/rickson-academy")

      assert {:ok, gym} = Matwork.Gyms.get_gym_by_slug("rickson-academy", actor: owner)
      assert gym.owner_id == owner.id
    end

    test "shows validation errors for a taken slug", %{conn: conn} do
      owner = generate(user())
      Matwork.Gyms.create_gym!("Existing Gym", "taken-slug", actor: owner)

      other_user = generate(user())
      conn = sign_in(conn, other_user)

      {:ok, view, _html} = live(conn, ~p"/gyms/new")

      html =
        view
        |> form("#gym-form", form: %{name: "New Gym", slug: "taken-slug"})
        |> render_submit()

      assert html =~ "has already been taken" or html =~ "taken"
    end
  end
end
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
mix test test/matwork_web/live/gym_new_live_test.exs
```

Expected: `3 tests, 0 failures`. If the exact validation-error copy in the second test doesn't match (Ash's uniqueness error message wording can vary by identity name), inspect the rendered `html` and adjust the assertion to match the actual message — the point of the test is that *some* error renders, not the exact string.

- [ ] **Step 5: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/matwork_web/live/gym_new_live.ex lib/matwork_web/router.ex \
  test/matwork_web/live/gym_new_live_test.exs
git commit -m "Add GymNewLive for creating a gym"
```

---

### Task 4: Gym home LiveView (roster + invite) and invite email

**Files:**
- Create: `lib/matwork/gyms/invite/senders/send_invite_email.ex`
- Create: `lib/matwork/gyms/invite/changes/send_invite_email.ex`
- Modify: `lib/matwork/gyms/invite.ex`
- Create: `lib/matwork_web/live/gym_show_live.ex`
- Modify: `lib/matwork_web/router.ex`
- Test: `test/matwork_web/live/gym_show_live_test.exs`

**Interfaces:**
- Consumes: `Matwork.Gyms.list_memberships!/1`, `Matwork.Gyms.form_to_create_invite/1` (Task 1's `AshPhoenix` extension), `StalwartUI.RosterTable.roster_table/1`, `StalwartUI.InviteForm.invite_form/1` (Task 2), `MatworkWeb.GymLiveAuth` (Task 1).
- Produces: route `/g/:slug` — the gym's home page.

- [ ] **Step 1: Write the invite email sender**

Create `lib/matwork/gyms/invite/senders/send_invite_email.ex`:

```elixir
defmodule Matwork.Gyms.Invite.Senders.SendInviteEmail do
  @moduledoc "Sends an email inviting someone to join a gym."
  use MatworkWeb, :verified_routes

  import Swoosh.Email
  alias Matwork.Mailer

  def send(invite, gym) do
    new()
    |> from({"noreply", "matt@stalwartstudios.com"})
    |> to(to_string(invite.email))
    |> subject("You're invited to join #{gym.name}")
    |> html_body(body(invite: invite, gym: gym))
    |> Mailer.deliver!()
  end

  defp body(params) do
    invite = params[:invite]
    gym = params[:gym]

    """
    <p>You've been invited to join #{gym.name} on Matwork as a #{invite.role}.</p>
    <p><a href="#{url(~p"/g/#{gym.slug}/invite/#{invite.token}")}">Accept your invite</a></p>
    """
  end
end
```

- [ ] **Step 2: Write the change that sends it**

Create `lib/matwork/gyms/invite/changes/send_invite_email.ex`:

```elixir
defmodule Matwork.Gyms.Invite.Changes.SendInviteEmail do
  @moduledoc "Emails the invite link after a successful Invite creation."
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    actor = context.actor

    Ash.Changeset.after_action(changeset, fn changeset, invite ->
      invite = Ash.load!(invite, :gym, tenant: changeset.tenant, actor: actor)
      Matwork.Gyms.Invite.Senders.SendInviteEmail.send(invite, invite.gym)
      {:ok, invite}
    end)
  end
end
```

`actor: actor` here is the owner/instructor who is creating the invite — no `authorize?: false` needed, since `Gym`'s `:read` policy is public (`always()`, see session 2's plan Deviation #2).

- [ ] **Step 3: Wire the change into `Invite`'s `:create` action**

Modify `lib/matwork/gyms/invite.ex`, changing:

```elixir
    create :create do
      accept [:email, :role]
      change Matwork.Gyms.Invite.Changes.GenerateToken
    end
```

to:

```elixir
    create :create do
      accept [:email, :role]
      change Matwork.Gyms.Invite.Changes.GenerateToken
      change Matwork.Gyms.Invite.Changes.SendInviteEmail
    end
```

- [ ] **Step 4: Write the LiveView**

Create `lib/matwork_web/live/gym_show_live.ex`:

```elixir
defmodule MatworkWeb.GymShowLive do
  use MatworkWeb, :live_view

  import StalwartUI.RosterTable
  import StalwartUI.InviteForm

  alias Matwork.Gyms

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(_params, _session, socket) do
    {:ok, assign_roster_and_form(socket)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :invite_form, AshPhoenix.Form.validate(socket.assigns.invite_form, params))}
  end

  def handle_event("invite", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.invite_form, params: params) do
      {:ok, _invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invite sent")
         |> assign_roster_and_form()}

      {:error, form} ->
        {:noreply, assign(socket, :invite_form, form)}
    end
  end

  defp assign_roster_and_form(socket) do
    gym = socket.assigns.current_gym
    actor = socket.assigns.current_user
    membership = socket.assigns.current_membership

    if membership do
      memberships = Gyms.list_memberships!(actor: actor, tenant: gym.id, load: [:user])

      invite_form =
        if membership.role in [:owner, :instructor] do
          Gyms.form_to_create_invite(actor: actor, tenant: gym.id) |> to_form()
        end

      socket
      |> assign(:memberships, memberships)
      |> assign(:invite_form, invite_form)
    else
      socket
      |> assign(:memberships, [])
      |> assign(:invite_form, nil)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>{@current_gym.name}</.header>

      <div :if={is_nil(@current_membership)}>
        <p>You don't have access to this gym yet.</p>
      </div>

      <div :if={@current_membership}>
        <.roster_table id="roster" memberships={@memberships} />

        <div :if={@invite_form}>
          <.invite_form form={@invite_form} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Add the route**

Modify `lib/matwork_web/router.ex`, changing:

```elixir
  scope "/g/:slug", MatworkWeb do
    pipe_through [:browser, :gym]

    # LiveViews are added inside this scope in later tasks (Task 3 for
    # /gyms/new — a sibling scope, not gym-scoped — and Tasks 4/5 for the
    # gym home page and accept-invite page here).
  end
```

to:

```elixir
  scope "/g/:slug", MatworkWeb do
    pipe_through [:browser, :gym]

    ash_authentication_live_session :gym_routes do
      live "/", GymShowLive
    end
  end
```

- [ ] **Step 6: Write the failing tests**

Create `test/matwork_web/live/gym_show_live_test.exs`:

```elixir
defmodule MatworkWeb.GymShowLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  alias Matwork.Gyms

  describe "as the gym's owner" do
    test "shows the roster and an invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      conn = sign_in(conn, owner)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert html =~ to_string(Ash.CiString.value(student.email))
      assert has_element?(view, "#invite-form")
    end

    test "sending an invite adds it and re-renders the invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      conn = sign_in(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}")

      html =
        view
        |> form("#invite-form", form: %{email: "student@example.com", role: "student"})
        |> render_submit()

      assert html =~ "Invite sent"
      assert length(Gyms.list_invites!(actor: owner, tenant: gym.id)) == 1
    end
  end

  describe "as a student" do
    test "shows the roster but no invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      conn = sign_in(conn, student)
      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}")

      refute has_element?(view, "#invite-form")
    end
  end

  describe "as someone with no membership" do
    test "shows the access message instead of the roster", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      stranger = generate(user())

      conn = sign_in(conn, stranger)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert html =~ "don't have access"
      refute has_element?(view, "#roster")
    end
  end

  test "404s for a nonexistent gym", %{conn: conn} do
    owner = generate(user())
    conn = sign_in(conn, owner)

    assert conn |> get(~p"/g/does-not-exist") |> Phoenix.ConnTest.response(404)
  end
end
```

- [ ] **Step 7: Run the tests and verify they pass**

```bash
mix test test/matwork_web/live/gym_show_live_test.exs
```

Expected: `5 tests, 0 failures`.

- [ ] **Step 8: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/matwork/gyms/invite/senders/send_invite_email.ex \
  lib/matwork/gyms/invite/changes/send_invite_email.ex lib/matwork/gyms/invite.ex \
  lib/matwork_web/live/gym_show_live.ex lib/matwork_web/router.ex \
  test/matwork_web/live/gym_show_live_test.exs
git commit -m "Add GymShowLive with roster, invite form, and invite email"
```

---

### Task 5: Accept-invite LiveView — the invite → join critical flow

**Files:**
- Create: `lib/matwork_web/live/invite_accept_live.ex`
- Modify: `lib/matwork_web/router.ex`
- Test: `test/matwork_web/live/invite_accept_live_test.exs`

**Interfaces:**
- Consumes: `Matwork.Gyms.accept_invite/2` (session 2), `MatworkWeb.GymLiveAuth` (Task 1).
- Produces: route `/g/:slug/invite/:token`. This is the LiveView-level "invite → join" test `docs/design.md` §9 and `CLAUDE.md` require.

- [ ] **Step 1: Write the LiveView**

Create `lib/matwork_web/live/invite_accept_live.ex`:

```elixir
defmodule MatworkWeb.InviteAcceptLive do
  use MatworkWeb, :live_view

  alias Matwork.Gyms

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, token: token, status: nil)

    {:ok, resolve(socket)}
  end

  defp resolve(socket) do
    gym = socket.assigns.current_gym

    case socket.assigns.current_user do
      nil ->
        assign(socket, :status, :needs_sign_in)

      user ->
        case Gyms.accept_invite(socket.assigns.token, actor: user, tenant: gym.id) do
          {:ok, _membership} ->
            socket
            |> put_flash(:info, "Welcome to #{gym.name}!")
            |> push_navigate(to: ~p"/g/#{gym.slug}")

          {:error, _error} ->
            assign(socket, :status, :invalid)
        end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Join {@current_gym.name}</.header>

      <div :if={@status == :needs_sign_in} id="invite-needs-sign-in">
        <p>You've been invited to join {@current_gym.name}. Sign in to accept.</p>
        <.link navigate={~p"/sign-in"} class="btn btn-primary">Sign in</.link>
        <p class="text-sm mt-2">After signing in, come back to this link to finish joining.</p>
      </div>

      <div :if={@status == :invalid} id="invite-invalid">
        <p>This invite link is invalid, expired, or already used.</p>
      </div>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 2: Add the route**

Modify `lib/matwork_web/router.ex`, changing:

```elixir
  scope "/g/:slug", MatworkWeb do
    pipe_through [:browser, :gym]

    ash_authentication_live_session :gym_routes do
      live "/", GymShowLive
    end
  end
```

to:

```elixir
  scope "/g/:slug", MatworkWeb do
    pipe_through [:browser, :gym]

    ash_authentication_live_session :gym_routes do
      live "/", GymShowLive
      live "/invite/:token", InviteAcceptLive
    end
  end
```

- [ ] **Step 3: Write the failing tests**

Create `test/matwork_web/live/invite_accept_live_test.exs`:

```elixir
defmodule MatworkWeb.InviteAcceptLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  alias Matwork.Gyms

  describe "signed out" do
    test "shows a sign-in prompt", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-needs-sign-in")
    end
  end

  describe "signed in with a matching email" do
    test "accepts the invite and redirects to the gym home page", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      student = generate(user(email: "student@example.com"))
      conn = sign_in(conn, student)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert to == ~p"/g/#{gym.slug}"

      membership = Gyms.get_membership_for_user!(student.id, actor: student, tenant: gym.id)
      assert membership.role == :student
      assert membership.status == :active
    end
  end

  describe "signed in with a non-matching email" do
    test "shows the invalid-invite message", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      other_user = generate(user())
      conn = sign_in(conn, other_user)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-invalid")
    end
  end

  describe "an already-accepted invite" do
    test "shows the invalid-invite message on the second attempt", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      first_student = generate(user(email: "student@example.com"))
      Gyms.accept_invite!(invite.token, actor: first_student, tenant: gym.id)

      second_student = generate(user(email: "student@example.com"))
      conn = sign_in(conn, second_student)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-invalid")
    end
  end
end
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
mix test test/matwork_web/live/invite_accept_live_test.exs
```

Expected: `4 tests, 0 failures`. If the redirect assertion shape in the second test doesn't match (the exact `{:error, {:live_redirect, ...}}` vs `{:error, {:redirect, ...}}` tuple shape can depend on whether the mount is treated as a dead render or a live navigation in the test), adjust to match `live/2`'s actual return — the mount always ends in a `push_navigate`, so some redirect-shaped error tuple is expected either way.

- [ ] **Step 5: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/matwork_web/live/invite_accept_live.ex lib/matwork_web/router.ex \
  test/matwork_web/live/invite_accept_live_test.exs
git commit -m "Add InviteAcceptLive, closing the invite-to-join loop"
```

---

### Task 6: Fly deploy scaffold (no launch)

**Files:**
- Generated by `mix phx.gen.release --docker`: `Dockerfile`, `.dockerignore`, `rel/overlays/bin/*`, `lib/matwork/release.ex`
- Create: `fly.toml`
- Create: `docs/deploy.md`

**Interfaces:**
- Consumes: nothing (infrastructure scaffolding, independent of Tasks 1–5).
- Produces: a buildable production Docker image and a `fly.toml` ready for `fly launch --no-deploy` / `fly deploy`, plus documented manual steps for you to run with your own Fly credentials.

- [ ] **Step 1: Generate the release files**

```bash
mix phx.gen.release --docker
```

Expected output includes something like:

```
* creating rel/overlays/bin/server
* creating rel/overlays/bin/server.bat
* creating rel/overlays/bin/migrate
* creating rel/overlays/bin/migrate.bat
* creating lib/matwork/release.ex
* creating Dockerfile
* creating .dockerignore
```

This also updates `mix.exs` if needed (adds a `:tailwind`/`:esbuild` asset-build step reference for the release, if not already present) and may add a release config block to `mix.exs`'s `project/0`. Review the diff; it's igniter/generator-owned code, not hand-written, so no manual edits are expected here.

- [ ] **Step 2: Confirm the Docker image builds**

```bash
docker build -t matwork-release-check .
```

Expected: the build completes without error. This does *not* require a running Postgres or app secrets — it's a compile-only check. If Docker isn't installed/running locally, skip this step and note it in the task's completion notes; it's a nice-to-have verification, not a blocker (the Dockerfile itself is still generated and correct).

- [ ] **Step 3: Write `fly.toml`**

Create `fly.toml` (values here match `mix.exs`'s `app: :matwork` and a plausible Fly app name — the real app name gets assigned/confirmed when you run `fly launch`, at which point this file's `app` key should be updated to match):

```toml
# fly.toml app configuration file
# See https://fly.io/docs/reference/configuration/ for information on how to use this file.

app = "matwork"
primary_region = "iad"
console_command = "/app/bin/matwork remote"

[build]

[env]
  PHX_HOST = "matwork.fly.dev"
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 0
  processes = ["app"]

[[vm]]
  memory = "1gb"
  cpu_kind = "shared"
  cpus = 1

[deploy]
  release_command = "/app/bin/migrate"
```

- [ ] **Step 4: Write the manual deploy steps**

Create `docs/deploy.md`:

```markdown
# Deploying to Fly.io

This app's Docker image and `fly.toml` are scaffolded (`Dockerfile`,
`.dockerignore`, `rel/overlays/`, `lib/matwork/release.ex`, `fly.toml`) but
launching and deploying requires your own Fly.io account and CLI
authentication, so it isn't automated. Steps to run yourself:

## First-time setup

1. Install the Fly CLI if you haven't: `curl -L https://fly.io/install.sh | sh`
2. `fly auth login`
3. From the project root: `fly launch --no-deploy` — this will detect the
   existing `fly.toml` and Dockerfile, ask to confirm/adjust the app name
   and region, and create the Fly app without deploying yet. Update the
   `app` key in `fly.toml` if Fly assigns a different name than the
   placeholder `"matwork"`.
4. Provision Postgres: `fly postgres create` (or attach an existing Fly
   Postgres cluster with `fly postgres attach`).
5. Set secrets (the app raises on boot without these — see
   `config/runtime.exs`):
   ```
   fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
   fly secrets set TOKEN_SIGNING_SECRET=$(mix phx.gen.secret)
   ```
   Mailer secrets (Resend/Postmark API key) once a production Swoosh
   adapter is configured — not yet needed for this milestone, since
   `config/prod.exs` still needs that adapter wired in before it matters
   in production. Local dev keeps using `Swoosh.Adapters.Local`.

## Every deploy after that

```
fly deploy
```

`release_command` in `fly.toml` runs `/app/bin/migrate` automatically before
each deploy's new version goes live, so `mix ash.migrate`-generated
migrations ship on every deploy without a separate manual step.

## Verifying a deploy

```
fly status
fly logs
```

Visit `https://<app-name>.fly.dev` (or the custom `PHX_HOST` you configure)
to confirm the app boots and the `/` route responds.
```

- [ ] **Step 5: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green — this task touches no application code, so this step mainly guards against the generator having introduced anything the formatter/credo would flag.

- [ ] **Step 6: Commit**

```bash
git add Dockerfile .dockerignore rel/ lib/matwork/release.ex fly.toml docs/deploy.md mix.exs mix.lock
git commit -m "Scaffold Fly.io deploy pipeline (Dockerfile, fly.toml, manual steps)"
```

---

## After this session

Demoable end state, matching `docs/design.md`'s Milestone 0 demo almost exactly: sign in via magic link, create a gym at `/gyms/new` (becoming its owner), land on `/g/:slug` and invite a student by email (which emails them — check `/dev/mailbox` in dev — and adds the pending invite), and a student who clicks the invite link, signs in via magic link with the matching email, and is dropped back onto the gym's home page as an active member. Tenancy isolation and the roster-visibility/invite-role policies from session 2 are now exercised end-to-end through real LiveViews, not just direct code-interface calls in tests.

Not in this session, deliberately: Fly is scaffolded but not launched (needs your credentials); no LiveView tests for "subscribe → watch" (Milestone 2, no `Subscription`/`Lesson` resources exist yet); no `mark_invite_accepted` UI for revoking/re-sending an invite (design.md doesn't call for it in the POC); the invite form's role options in `StalwartUI.InviteForm` default to `[:instructor, :student]` but `GymShowLive` doesn't yet restrict an instructor-actor's visible role options to `[:student]` only in the UI (the `CanInviteRole` policy already rejects an instructor granting `:owner`/`:instructor` server-side, so this is a UX polish gap, not a security gap — worth a follow-up before Milestone 3's "hand an account to a friendly black belt" demo). The natural next session is Milestone 1: Curriculum + Media domains, Mux direct upload, and the first video playback.
