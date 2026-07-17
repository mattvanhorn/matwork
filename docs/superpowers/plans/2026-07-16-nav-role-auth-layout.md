# Role/Auth-Aware Nav Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the default Phoenix-scaffold nav header in `MatworkWeb.Layouts.app/1` with a Matwork-specific header that shows the right brand mark and actions for the current auth state.

**Architecture:** `Layouts.app/1` gains two new optional assigns, `current_user` and `current_gym` (both default `nil`), which its three call sites (`GymShowLive`, `GymNewLive`, `InviteAcceptLive`) already have available on their sockets via the existing `MatworkWeb.LiveUserAuth` and `MatworkWeb.GymLiveAuth` on_mount hooks. The component branches on those two assigns to pick a brand mark (gym name vs. "Matwork") and a right-hand action set (signed-in vs. signed-out).

**Tech Stack:** Phoenix LiveView, Phoenix.Component (HEEx), Phoenix.LiveViewTest, ExUnit.

## Global Constraints

- Change is confined to `lib/matwork_web/components/layouts.ex` and its three call sites: `lib/matwork_web/live/gym_show_live.ex`, `lib/matwork_web/live/gym_new_live.ex`, `lib/matwork_web/live/invite_accept_live.ex`. Per spec (`docs/superpowers/specs/2026-07-16-nav-role-auth-layout-design.md`), do NOT touch: the `/` home page (`lib/matwork_web/controllers/page_html/home.html.heex` — it doesn't call `Layouts.app`), the sign-in/sign-out pages (they use `AshAuthentication.Phoenix.LayoutView`, not `Layouts.app`), or add any footer or cross-tenant "list my gyms" query.
- No role-specific nav items. Owner/instructor-only actions (roster, invite form) stay inline on the gym page body exactly as they are today — do not move or duplicate them into the nav.
- "Sign out" in the nav is a plain link to `/sign-out`, the existing two-step confirmation page. Do not change that flow or add a one-click sign-out.
- Before committing: run `mix format`, `mix credo --strict`, and `mix test`, and confirm all three are clean/green (project workflow rule).

---

### Task 1: Role/auth-aware `Layouts.app` nav bar

**Files:**
- Modify: `lib/matwork_web/components/layouts.ex:28-63` (the `app/1` attrs and header markup)
- Modify: `lib/matwork_web/live/gym_show_live.ex:62` (the `<Layouts.app>` call)
- Modify: `lib/matwork_web/live/gym_new_live.ex:29` (the `<Layouts.app>` call)
- Modify: `lib/matwork_web/live/invite_accept_live.ex:37` (the `<Layouts.app>` call)
- Test: `test/matwork_web/live/gym_show_live_test.exs` (new `describe "nav bar"` block)
- Test: `test/matwork_web/live/gym_new_live_test.exs` (new `describe "nav bar"` block)
- Test: `test/matwork_web/live/invite_accept_live_test.exs` (extend the existing `describe "signed out"` test)

**Interfaces:**
- Consumes: `socket.assigns.current_user` (a `Matwork.Accounts.User` struct or `nil`, already assigned by `MatworkWeb.LiveUserAuth`'s `on_mount` hooks in all three LiveViews). `socket.assigns.current_gym` (a `Matwork.Gyms.Gym` struct or `nil`, already assigned by `MatworkWeb.GymLiveAuth`'s `on_mount` hook in `GymShowLive` and `InviteAcceptLive`; not present in `GymNewLive`, which is not gym-scoped).
- Produces: `MatworkWeb.Layouts.app/1` now accepts `current_user` (default `nil`) and `current_gym` (default `nil`) attrs. The rendered header exposes stable element ids for testing: `#nav-brand`, `#nav-user-email`, `#nav-create-gym`, `#nav-sign-out`, `#nav-sign-in`.

- [ ] **Step 1: Write failing nav tests for `GymShowLive`**

Add this `describe` block to `test/matwork_web/live/gym_show_live_test.exs` (place it after the existing `describe "as someone with no membership"` block, before the final `test "404s for a nonexistent gym"`):

```elixir
  describe "nav bar" do
    test "shows the gym name as the brand mark and signed-in actions for the owner", %{
      conn: conn
    } do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      conn = sign_in(conn, owner)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert has_element?(view, "#nav-brand", gym.name)
      assert has_element?(view, "#nav-user-email", to_string(Ash.CiString.value(owner.email)))
      assert has_element?(view, "#nav-create-gym")
      assert has_element?(view, "#nav-sign-out")
      refute has_element?(view, "#nav-sign-in")
      refute html =~ "phoenixframework.org"
      refute html =~ "Website"
    end

    test "shows the gym name as the brand mark and a sign-in prompt for an anonymous visitor",
         %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}")

      assert has_element?(view, "#nav-brand", gym.name)
      assert has_element?(view, "#nav-sign-in")
      refute has_element?(view, "#nav-user-email")
      refute has_element?(view, "#nav-create-gym")
      refute has_element?(view, "#nav-sign-out")
    end
  end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `mix test test/matwork_web/live/gym_show_live_test.exs`
Expected: the two new tests in `describe "nav bar"` FAIL (no `#nav-brand`, `#nav-user-email`, etc. exist yet — the current header only has the Phoenix scaffold links). All pre-existing tests in the file still PASS.

- [ ] **Step 3: Write a failing nav test for `GymNewLive`**

Add this `describe` block to `test/matwork_web/live/gym_new_live_test.exs` (after the existing `describe "mount"` block):

```elixir
  describe "nav bar" do
    test "shows the Matwork brand mark and signed-in actions", %{conn: conn} do
      owner = generate(user())
      conn = sign_in(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/gyms/new")

      assert has_element?(view, "#nav-brand", "Matwork")
      assert has_element?(view, "#nav-user-email", to_string(Ash.CiString.value(owner.email)))
      assert has_element?(view, "#nav-create-gym")
      assert has_element?(view, "#nav-sign-out")
    end
  end
```

This test file doesn't yet import `Matwork.Generator`'s `generate/1` output usage beyond what's already imported — no new imports needed, `generate` and `user/0` are already imported at the top of the file.

- [ ] **Step 4: Run the new test to verify it fails**

Run: `mix test test/matwork_web/live/gym_new_live_test.exs`
Expected: the new `describe "nav bar"` test FAILS. Pre-existing tests still PASS.

- [ ] **Step 5: Extend the `InviteAcceptLive` "signed out" test to assert on the nav**

In `test/matwork_web/live/invite_accept_live_test.exs`, replace the existing `describe "signed out"` block (lines 9-19) with:

```elixir
  describe "signed out" do
    test "shows a sign-in prompt", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-needs-sign-in")
      assert has_element?(view, "#nav-brand", gym.name)
      assert has_element?(view, "#nav-sign-in")
    end
  end
```

- [ ] **Step 6: Run the updated test to verify the new assertions fail**

Run: `mix test test/matwork_web/live/invite_accept_live_test.exs`
Expected: the `"shows a sign-in prompt"` test FAILS on the new `#nav-brand`/`#nav-sign-in` assertions (the pre-existing `#invite-needs-sign-in` assertion still passes). Other tests in the file still PASS.

- [ ] **Step 7: Rewrite `Layouts.app/1`**

Replace lines 14-73 of `lib/matwork_web/components/layouts.ex` (the `@doc` block through the end of `def app/1`) with:

```elixir
  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_user, :map,
    default: nil,
    doc: "the signed-in Matwork.Accounts.User, or nil if not signed in"

  attr :current_gym, :map,
    default: nil,
    doc: "the Matwork.Gyms.Gym in scope for this page, or nil outside a gym context"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      if assigns.current_gym do
        assigns
        |> assign(:brand_label, assigns.current_gym.name)
        |> assign(:brand_href, ~p"/g/#{assigns.current_gym.slug}")
      else
        assigns
        |> assign(:brand_label, "Matwork")
        |> assign(:brand_href, ~p"/")
      end

    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={@brand_href} id="nav-brand" class="flex-1 flex w-fit items-center gap-2 text-sm font-semibold">
          {@brand_label}
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <.theme_toggle />
          </li>
          <li :if={@current_user}>
            <span id="nav-user-email" class="text-sm">{to_string(@current_user.email)}</span>
          </li>
          <li :if={@current_user}>
            <.link navigate={~p"/gyms/new"} id="nav-create-gym" class="btn btn-ghost">Create a gym</.link>
          </li>
          <li :if={@current_user}>
            <.link navigate={~p"/sign-out"} id="nav-sign-out" class="btn btn-ghost">Sign out</.link>
          </li>
          <li :if={!@current_user}>
            <.link navigate={~p"/sign-in"} id="nav-sign-in" class="btn btn-primary">Sign in</.link>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end
```

This removes the `current_scope` attr (unused elsewhere in the codebase) and the Phoenix "Website" / "GitHub" / "Get Started" links and version badge.

- [ ] **Step 8: Wire `current_user`/`current_gym` into the three call sites**

In `lib/matwork_web/live/gym_show_live.ex`, change:

```elixir
    <Layouts.app flash={@flash}>
```

to:

```elixir
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
```

In `lib/matwork_web/live/gym_new_live.ex`, change:

```elixir
    <Layouts.app flash={@flash}>
```

to:

```elixir
    <Layouts.app flash={@flash} current_user={@current_user}>
```

In `lib/matwork_web/live/invite_accept_live.ex`, change:

```elixir
    <Layouts.app flash={@flash}>
```

to:

```elixir
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
```

- [ ] **Step 9: Run all three test files to verify they now pass**

Run: `mix test test/matwork_web/live/gym_show_live_test.exs test/matwork_web/live/gym_new_live_test.exs test/matwork_web/live/invite_accept_live_test.exs`
Expected: PASS (all tests, old and new).

- [ ] **Step 10: Format and lint**

Run: `mix format`
Run: `mix credo --strict`
Expected: `mix format` makes no further changes (or only whitespace changes you accept); `mix credo --strict` reports no new issues in the changed files.

- [ ] **Step 11: Run the full test suite**

Run: `mix test`
Expected: PASS, no regressions elsewhere (nothing else in the codebase asserts on the removed nav markup — confirmed during spec research).

- [ ] **Step 12: Commit**

```bash
git add lib/matwork_web/components/layouts.ex \
  lib/matwork_web/live/gym_show_live.ex \
  lib/matwork_web/live/gym_new_live.ex \
  lib/matwork_web/live/invite_accept_live.ex \
  test/matwork_web/live/gym_show_live_test.exs \
  test/matwork_web/live/gym_new_live_test.exs \
  test/matwork_web/live/invite_accept_live_test.exs
git commit -m "Replace Phoenix-scaffold nav with a role/auth-aware header

Layouts.app now shows the current gym's name (or \"Matwork\" outside a
gym context) as the brand mark, and signed-in-vs-signed-out actions
(email + Create a gym + Sign out, or Sign in) instead of the default
Website/GitHub/Get Started scaffold links."
```
