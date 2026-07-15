# Milestone 0, Session 2: Gym, Membership, and Invite Resources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `Matwork.Gyms` domain with `Gym`, `Membership`, and `Invite` Ash resources, wired with attribute-multitenancy and policies, so a user can create a gym (becoming its owner), invite a student by email, and have that student accept the invite into an active membership — with a full allow/deny policy test suite.

**Architecture:** One new Ash domain (`Matwork.Gyms`) with three resources. `Gym` is a **global** resource (per `docs/design.md` §3/§4 — gyms, like users, are not scoped to a tenant, they *are* a tenant root). `Membership` and `Invite` are **tenant-scoped** on `gym_id` via Ash's `:attribute` multitenancy strategy. Authorization is enforced entirely in resource policies (`Ash.Policy.Authorizer`), never in test helpers or future LiveViews — the policies you write here are the actual product feature ("the deny paths are the product," per `CLAUDE.md`). No LiveViews, routing, tenant-resolution plug, or Fly deploy pipeline are in scope for this session — those are later Milestone 0 work; this session is resources + policies + tests only, per the request.

**Tech Stack:** Elixir 1.18 / Ash 3.x / `ash_postgres` / ExUnit / `Ash.Generator` for test fixtures.

## Global Constraints

- Global resources: `User`, `Token`, `Gym`, `WebhookEvent`. Everything else is attribute-multitenant on `gym_id`. (`CLAUDE.md`)
- Every Ash call passes `actor:`; every call on a tenant-scoped resource passes `tenant:`. No `authorize?: false` outside seeds, migrations, and system-actor webhook jobs — and flag it in the diff summary when used. (`CLAUDE.md`)
- Authorization lives in resource policies, never in LiveViews or controllers. (`CLAUDE.md`) — N/A this session (no LiveViews), but the resource policies written here are what that future web layer will lean on.
- After changing resources, run `mix ash.codegen <descriptive_name>`. Don't hand-write migrations. (`CLAUDE.md`)
- Before every commit: `mix format`, `mix credo --strict`, `mix test` — all green. (`CLAUDE.md`)
- Small commits, one concern each, imperative subject lines. (`CLAUDE.md`)
- Every policy gets tests for allow AND deny paths. The deny paths are the product. (`CLAUDE.md`)
- Test tenancy isolation explicitly: a user in gym A must not read/act on gym B's rows. (`CLAUDE.md`)
- `mix usage_rules.docs <Module>` / `mix usage_rules.search_docs <query> -p ash` are available if an implementer needs to double check an Ash API call beyond what's specified below.

## Deviations from `docs/design.md` — flagged per `CLAUDE.md` ("if code and design doc disagree, say so")

1. **Primary keys are UUID, not bigserial.** §4 of `design.md` says "ids are bigserial for the POC." The session-1 scaffold already generated `Matwork.Accounts.User` with `uuid_primary_key :id` (via the `ash_authentication` installer's defaults). To keep `Gym.owner_id`, `Membership.user_id`, and all future FKs consistent with the existing `User` resource, this plan uses `uuid_primary_key :id` on `Gym`, `Membership`, and `Invite` too, rather than mixing key types. Worth a one-line callout to the human at the next design review; not re-litigated here.
2. **Gym read policy is public (`always()`).** `design.md` doesn't specify Gym read visibility explicitly, only "first policies (roster visibility)" for Milestone 0. Because a future tenant-resolution plug must look up a `Gym` by `slug` for *any* visitor (including unauthenticated ones, to render `/g/:slug` at all), `Gym`'s `:read` action is public. `stripe_account_id` and `stripe_onboarding_state` are therefore technically publicly readable in this session — there are no field policies yet. This is acceptable for the POC (no LiveView renders these fields to non-owners), but should get a field policy before Milestone 2 exposes billing UI. Flagged, not fixed, here.
3. **Invite token possession is the authorization boundary for accepting an invite**, mirroring the existing `AshAuthentication` magic-link pattern already in this codebase (`Matwork.Accounts.User`'s `sign_in_with_magic_link` action is publicly callable and gated only by possessing a valid token). `Invite`'s `:get_by_token` and `:mark_accepted` actions use `authorize_if always()` rather than a role-based policy, because the actor accepting an invite does not yet have a `Membership` in the tenant — by definition they can't pass an "is an active member" check. Validity is enforced by business-logic validations (token exists, not already accepted) inside the action, not by the policy layer. This keeps the "no `authorize?: false` outside seeds/migrations/webhook jobs" rule intact — every call in this plan passes real `actor:`/`tenant:` and goes through policies; nothing bypasses authorization.

## File Structure

```
lib/matwork/gyms.ex                                    # Ash.Domain — resources + code interfaces
lib/matwork/gyms/gym.ex                                 # Gym resource (global)
lib/matwork/gyms/gym/changes/create_owner_membership.ex # after_action hook: gym create -> owner membership
lib/matwork/gyms/membership.ex                           # Membership resource (tenant-scoped)
lib/matwork/gyms/membership/changes/accept_invite.ex     # ties Invite lookup into Membership upsert
lib/matwork/gyms/invite.ex                                # Invite resource (tenant-scoped)
lib/matwork/gyms/invite/changes/generate_token.ex         # random token generator
lib/matwork/gyms/checks/active_member.ex                  # custom Ash.Policy.SimpleCheck
config/config.exs                                          # register Matwork.Gyms in ash_domains, add fee config
test/support/generator.ex                                  # Ash.Generator-based test fixtures
test/matwork/gyms/gym_test.exs
test/matwork/gyms/membership_test.exs
test/matwork/gyms/invite_test.exs
```

Each resource gets its own file (matches the existing `lib/matwork/accounts/user.ex` / `token.ex` split). Change modules that only exist to serve one resource's one action live under that resource's namespace (`gym/changes/`, `membership/changes/`, `invite/changes/`), matching the "custom modules, not anonymous functions" guidance in the Ash usage rules. The one cross-resource check (`ActiveMember`, used by both `Membership` and `Invite` policies) lives at the domain level under `gyms/checks/`.

---

### Task 1: `Matwork.Gyms` domain + `Gym` resource

**Files:**
- Create: `lib/matwork/gyms.ex`
- Create: `lib/matwork/gyms/gym.ex`
- Modify: `config/config.exs`
- Create: `test/support/generator.ex`
- Test: `test/matwork/gyms/gym_test.exs`

**Interfaces:**
- Produces: `Matwork.Gyms.create_gym!(name, slug, opts)`, `Matwork.Gyms.get_gym_by_id!(id, opts)`, `Matwork.Gyms.get_gym_by_slug!(slug, opts)` — all later tasks and any future web layer call the domain, never `Ash.create!(Matwork.Gyms.Gym, ...)` directly.
- Produces: `Matwork.Generator.user(opts)` — a `stream_data` generator (call `Matwork.Generator.generate(user())` or `Ash.Generator.generate/1` to materialize) yielding a seeded `%Matwork.Accounts.User{}` with a globally-unique email. Later tasks' generators build on this.
- Consumes: nothing (first task).

- [ ] **Step 1: Register the domain and add fee config**

Add `Matwork.Gyms` to `ash_domains` and a config value for the default application fee percent.

In `config/config.exs`, change:

```elixir
config :matwork,
  ecto_repos: [Matwork.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Matwork.Accounts],
  ash_authentication: [return_error_on_invalid_magic_link_token?: true]
```

to:

```elixir
config :matwork,
  ecto_repos: [Matwork.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Matwork.Accounts, Matwork.Gyms],
  ash_authentication: [return_error_on_invalid_magic_link_token?: true],
  default_application_fee_percent: "10.0"
```

`Decimal` is a transitive dependency (via `ash`/`ecto`/`postgrex`) but is not yet loaded when
`config/config.exs` is evaluated in this project's build, so `Decimal.new("10.0")` cannot run
here — use the plain string literal. The `Gym` resource's `:decimal` attribute type casts it
to a proper `Decimal` at runtime when a `Gym` is created (verified: the stored/returned value
is `Decimal.new("10.0")`, not a string).

- [ ] **Step 2: Write the `Gym` resource**

Create `lib/matwork/gyms/gym.ex`:

```elixir
defmodule Matwork.Gyms.Gym do
  @moduledoc """
  A gym: the tenant root. Global resource — a gym's own row is not itself
  scoped to a tenant, and its slug must be resolvable by unauthenticated
  visitors (see the tenant-resolution plug planned for a later session).
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Gyms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "gyms"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :slug]
      change relate_actor(:owner)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :custom_domain, :ci_string do
      public? true
    end

    attribute :stripe_account_id, :string do
      public? true
    end

    attribute :stripe_onboarding_state, :atom do
      constraints one_of: [:none, :started, :complete]
      default :none
      allow_nil? false
      public? true
    end

    attribute :application_fee_percent, :decimal do
      allow_nil? false
      default fn -> Application.get_env(:matwork, :default_application_fee_percent) end
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, Matwork.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_custom_domain, [:custom_domain]
  end
end
```

- [ ] **Step 3: Create the domain module**

Create `lib/matwork/gyms.ex`:

```elixir
defmodule Matwork.Gyms do
  use Ash.Domain,
    otp_app: :matwork

  resources do
    resource Matwork.Gyms.Gym do
      define :create_gym, action: :create, args: [:name, :slug]
      define :get_gym_by_id, action: :read, get_by: [:id]
      define :get_gym_by_slug, action: :read, get_by: [:slug]
    end
  end
end
```

- [ ] **Step 4: Add the test generator support module**

Create `test/support/generator.ex`:

```elixir
defmodule Matwork.Generator do
  @moduledoc false
  use Ash.Generator

  alias Matwork.Accounts.User
  alias Matwork.Gyms.Gym

  def user(opts \\ []) do
    seed_generator(
      %User{
        email: sequence(:user_email, &"user-#{&1}@example.com")
      },
      overrides: opts
    )
  end

  def gym(opts \\ []) do
    {owner, opts} = Keyword.pop(opts, :owner)
    owner = owner || generate(user())

    changeset_generator(
      Gym,
      :create,
      defaults: [
        name: sequence(:gym_name, &"Gym #{&1}"),
        slug: sequence(:gym_slug, &"gym-#{&1}")
      ],
      actor: owner,
      overrides: opts
    )
  end
end
```

`elixirc_paths(:test)` already includes `"test/support"` (see `mix.exs`), so this compiles for the test env automatically.

- [ ] **Step 5: Run codegen and migrate**

```bash
mix ash.codegen add_gyms_domain_and_gym
mix ash.migrate
```

Expected: a new migration file under `priv/repo/migrations/` creating the `gyms` table with `id`, `name`, `slug`, `custom_domain`, `stripe_account_id`, `stripe_onboarding_state`, `application_fee_percent`, `owner_id`, timestamps, and the two unique indexes. It applies cleanly.

- [ ] **Step 6: Write the failing tests**

Create `test/matwork/gyms/gym_test.exs`:

```elixir
defmodule Matwork.Gyms.GymTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Gyms

  describe "create" do
    test "an authenticated user can create a gym and becomes its owner" do
      owner = generate(user())

      gym =
        Gyms.create_gym!("Rickson's Academy", "rickson-academy",
          actor: owner
        )

      assert gym.name == "Rickson's Academy"
      assert gym.owner_id == owner.id
    end

    test "no actor cannot create a gym" do
      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: nil)
      end
    end

    test "slug must be unique" do
      owner = generate(user())
      Gyms.create_gym!("Gym One", "same-slug", actor: owner)

      assert_raise Ash.Error.Invalid, fn ->
        Gyms.create_gym!("Gym Two", "same-slug", actor: owner)
      end
    end
  end

  describe "read" do
    test "an unauthenticated visitor can look up a gym by slug" do
      owner = generate(user())
      gym = Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      assert {:ok, found} = Gyms.get_gym_by_slug("rickson-academy", actor: nil)
      assert found.id == gym.id
    end

    test "looking up a nonexistent slug returns not found" do
      assert {:error, %Ash.Error.Invalid{}} =
               Gyms.get_gym_by_slug("does-not-exist", actor: nil)
    end
  end
end
```

- [ ] **Step 7: Run the tests and verify they pass**

```bash
mix test test/matwork/gyms/gym_test.exs
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
git add lib/matwork/gyms.ex lib/matwork/gyms/gym.ex config/config.exs \
  test/support/generator.ex test/matwork/gyms/gym_test.exs \
  priv/repo/migrations/ priv/resource_snapshots/
git commit -m "Add Gyms domain and Gym resource with create/read policies"
```

---

### Task 2: `Membership` resource

**Files:**
- Create: `lib/matwork/gyms/membership.ex`
- Create: `lib/matwork/gyms/checks/active_member.ex`
- Modify: `lib/matwork/gyms.ex`
- Test: `test/matwork/gyms/membership_test.exs`

**Interfaces:**
- Consumes: `Matwork.Generator.user/1`, `Matwork.Generator.gym/1` (Task 1).
- Produces: `Matwork.Gyms.create_owner_membership!(user_id, opts)`, `Matwork.Gyms.remove_membership!(membership, opts)`, `Matwork.Gyms.list_memberships!(opts)` — Task 3 (owner-membership auto-creation) and Task 5 (`accept_invite`) both build on this resource and its `Checks.ActiveMember` policy check.
- Produces: `Matwork.Gyms.Checks.ActiveMember` — a reusable `Ash.Policy.SimpleCheck`, used again by `Invite`'s policies in Task 4.

- [ ] **Step 1: Write the `ActiveMember` policy check**

Create `lib/matwork/gyms/checks/active_member.ex`:

```elixir
defmodule Matwork.Gyms.Checks.ActiveMember do
  @moduledoc """
  Policy check: does the actor have an active Membership, in the tenant the
  current request is scoped to, with one of the given roles?

  Defaults to any role (owner, instructor, or student) — i.e. "is the actor
  a member of this gym at all."
  """
  use Ash.Policy.SimpleCheck

  def describe(opts) do
    "actor has an active membership with role in #{inspect(opts[:roles] || [:owner, :instructor, :student])}"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, opts) do
    roles = opts[:roles] || [:owner, :instructor, :student]
    tenant = context.subject.tenant

    Matwork.Gyms.Membership
    |> Ash.Query.filter(user_id == ^actor.id and status == :active and role in ^roles)
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end
end
```

`authorize?: false` here is a deliberate, narrow exception: this check itself runs *inside* policy evaluation for another action, and its whole job is to answer "is the actor authorized" — recursively authorizing this internal existence check would be circular. This is the standard Ash pattern for writing policy checks that query the data layer (see `Ash.Policy.FilterCheck` docs) and is not the kind of application-code `authorize?: false` the iron rule is warning about, but it's flagged here per the rule's own instruction.

- [ ] **Step 2: Write the `Membership` resource**

Create `lib/matwork/gyms/membership.ex`:

```elixir
defmodule Matwork.Gyms.Membership do
  @moduledoc """
  A user's membership in a gym: their role and status on the roster.
  Tenant-scoped on `gym_id`.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Gyms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo Matwork.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  actions do
    defaults [:read]

    create :create_owner do
      accept [:user_id]
      change set_attribute(:role, :owner)
      change set_attribute(:status, :active)
    end

    update :remove do
      accept []
      change set_attribute(:status, :removed)
    end
  end

  policies do
    policy action(:create_owner) do
      authorize_if expr(gym.owner_id == ^actor(:id))
    end

    policy action_type(:read) do
      authorize_if Matwork.Gyms.Checks.ActiveMember
    end

    policy action(:remove) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:owner, :instructor, :student]
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :invited, :removed]
      default :active
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :gym, Matwork.Gyms.Gym do
      allow_nil? false
      public? true
    end

    belongs_to :user, Matwork.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_per_gym, [:user_id]
  end
end
```

Note: `belongs_to :gym` declares the `gym_id` attribute that `multitenancy do attribute :gym_id end` references — this is the documented Ash pattern (see `Ash.Resource`'s multitenancy guide), not a workaround. `identity :unique_user_per_gym` is automatically tenant-scoped by Ash's attribute multitenancy (uniqueness enforced within a `gym_id`, not globally) — a user can have one membership per gym, and memberships in different gyms don't collide.

- [ ] **Step 3: Register the resource and its code interfaces**

Modify `lib/matwork/gyms.ex`, changing:

```elixir
  resources do
    resource Matwork.Gyms.Gym do
      define :create_gym, action: :create, args: [:name, :slug]
      define :get_gym_by_id, action: :read, get_by: [:id]
      define :get_gym_by_slug, action: :read, get_by: [:slug]
    end
  end
```

to:

```elixir
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
    end
  end
```

- [ ] **Step 4: Run codegen and migrate**

```bash
mix ash.codegen add_membership
mix ash.migrate
```

Expected: a migration creating `memberships` with `id`, `gym_id`, `user_id`, `role`, `status`, timestamps, an FK to `gyms`, an FK to `users`, and the tenant-scoped unique index on `(gym_id, user_id)`.

- [ ] **Step 5: Add a `membership` generator**

Modify `test/support/generator.ex`, adding after the `gym/1` function. This seeds directly (bypassing the `:create_owner` action's owner-only policy) so it can produce fixtures for any role, not just owners — test fixtures for non-owner memberships are exactly the "authorization is not the focus" case the Ash testing usage rules call out:

```elixir
  def membership(opts \\ []) do
    {owning_gym, opts} = Keyword.pop(opts, :gym)
    {as_user, opts} = Keyword.pop(opts, :user)
    {role, opts} = Keyword.pop(opts, :role, :student)
    {status, opts} = Keyword.pop(opts, :status, :active)

    owning_gym = owning_gym || generate(gym())
    as_user = as_user || generate(user())

    seed_generator(
      %Matwork.Gyms.Membership{
        gym_id: owning_gym.id,
        user_id: as_user.id,
        role: role,
        status: status
      },
      overrides: opts
    )
  end
```

- [ ] **Step 6: Write the failing tests**

Create `test/matwork/gyms/membership_test.exs`:

```elixir
defmodule Matwork.Gyms.MembershipTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Gyms

  describe "create_owner" do
    test "the gym's owner can create their own owner membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      membership =
        Gyms.create_owner_membership!(owner.id, actor: owner, tenant: gym.id)

      assert membership.role == :owner
      assert membership.status == :active
      assert membership.user_id == owner.id
    end

    test "a non-owner cannot create an owner membership for themselves" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.create_owner_membership!(outsider.id, actor: outsider, tenant: gym.id)
      end
    end
  end

  describe "read (roster visibility)" do
    test "an active member can list the roster" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      roster = Gyms.list_memberships!(actor: student, tenant: gym.id)

      assert length(roster) == 1
    end

    test "someone with no membership in the gym cannot list the roster" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      stranger = generate(user())

      roster = Gyms.list_memberships!(actor: stranger, tenant: gym.id)

      assert roster == []
    end

    test "tenancy isolation: a member of gym A cannot see gym B's roster" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))
      member_a = generate(user())
      generate(membership(gym: gym_a, user: member_a, role: :student))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      generate(membership(gym: gym_b, user: generate(user()), role: :student))

      roster = Gyms.list_memberships!(actor: member_a, tenant: gym_b.id)

      assert roster == []
    end
  end

  describe "remove" do
    test "an owner can remove a student's membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      membership = generate(membership(gym: gym, user: student, role: :student))

      updated = Gyms.remove_membership!(membership, actor: owner, tenant: gym.id)

      assert updated.status == :removed
    end

    test "a student cannot remove another member" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      other_student = generate(user())
      membership = generate(membership(gym: gym, user: other_student, role: :student))
      generate(membership(gym: gym, user: student, role: :student))

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.remove_membership!(membership, actor: student, tenant: gym.id)
      end
    end
  end
end
```

- [ ] **Step 7: Run the tests and verify they pass**

```bash
mix test test/matwork/gyms/membership_test.exs
```

Expected: `7 tests, 0 failures`.

- [ ] **Step 8: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/matwork/gyms/membership.ex lib/matwork/gyms/checks/active_member.ex \
  lib/matwork/gyms.ex test/support/generator.ex test/matwork/gyms/membership_test.exs \
  priv/repo/migrations/ priv/resource_snapshots/
git commit -m "Add Membership resource with roster-visibility and role policies"
```

---

### Task 3: Wire `Gym.create` to auto-create the owner `Membership`

**Files:**
- Create: `lib/matwork/gyms/gym/changes/create_owner_membership.ex`
- Modify: `lib/matwork/gyms/gym.ex`
- Modify: `test/matwork/gyms/gym_test.exs`

**Interfaces:**
- Consumes: `Matwork.Gyms.create_owner_membership/2` (Task 2's code interface — note the non-raising form is used here since we're inside an `after_action` hook and want to return `{:error, _}` on failure rather than raise).
- Produces: after this task, `Matwork.Gyms.create_gym!/3` transactionally creates both the `Gym` row and its owner's `Membership` row — no change in the function's public signature, so nothing downstream needs updating.

No schema changes in this task — no `mix ash.codegen` needed.

- [ ] **Step 1: Write the change module**

Create `lib/matwork/gyms/gym/changes/create_owner_membership.ex`:

```elixir
defmodule Matwork.Gyms.Gym.Changes.CreateOwnerMembership do
  @moduledoc """
  After a gym is created, creates the owner's Membership row in the same
  transaction. Runs as an `after_action` hook so the new gym's id is
  available to use as the tenant.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, gym ->
      case Matwork.Gyms.create_owner_membership(gym.owner_id,
             actor: context.actor,
             tenant: gym.id
           ) do
        {:ok, _membership} -> {:ok, gym}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
```

- [ ] **Step 2: Wire it into the `Gym` resource's `:create` action**

Modify `lib/matwork/gyms/gym.ex`, changing:

```elixir
    create :create do
      accept [:name, :slug]
      change relate_actor(:owner)
    end
```

to:

```elixir
    create :create do
      accept [:name, :slug]
      change relate_actor(:owner)
      change Matwork.Gyms.Gym.Changes.CreateOwnerMembership
    end
```

- [ ] **Step 3: Write the failing test**

Modify `test/matwork/gyms/gym_test.exs`, adding a test inside the `"create"` describe block:

```elixir
    test "creating a gym also creates the owner's active owner Membership" do
      owner = generate(user())

      gym = Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      roster = Gyms.list_memberships!(actor: owner, tenant: gym.id)

      assert [%{role: :owner, status: :active, user_id: owner_id}] = roster
      assert owner_id == owner.id
    end
```

- [ ] **Step 4: Run the tests and verify they pass**

```bash
mix test test/matwork/gyms/gym_test.exs
```

Expected: `6 tests, 0 failures`.

- [ ] **Step 5: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/matwork/gyms/gym/changes/create_owner_membership.ex \
  lib/matwork/gyms/gym.ex test/matwork/gyms/gym_test.exs
git commit -m "Auto-create owner Membership when a Gym is created"
```

---

### Task 4: `Invite` resource

**Files:**
- Create: `lib/matwork/gyms/invite.ex`
- Create: `lib/matwork/gyms/invite/changes/generate_token.ex`
- Modify: `lib/matwork/gyms.ex`
- Test: `test/matwork/gyms/invite_test.exs`

**Interfaces:**
- Consumes: `Matwork.Gyms.Checks.ActiveMember` (Task 2).
- Produces: `Matwork.Gyms.create_invite!(email, role, opts)`, `Matwork.Gyms.get_invite_by_token!(token, opts)`, `Matwork.Gyms.mark_invite_accepted!(invite, opts)` — Task 5's `Membership.accept_invite` action consumes the latter two.

- [ ] **Step 1: Write the token-generation change**

Create `lib/matwork/gyms/invite/changes/generate_token.ex`:

```elixir
defmodule Matwork.Gyms.Invite.Changes.GenerateToken do
  @moduledoc "Generates a cryptographically random, URL-safe invite token."
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    token =
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    Ash.Changeset.force_change_attribute(changeset, :token, token)
  end
end
```

- [ ] **Step 2: Write the `Invite` resource**

Create `lib/matwork/gyms/invite.ex`:

```elixir
defmodule Matwork.Gyms.Invite do
  @moduledoc """
  An email invitation to join a gym with a given role. Tenant-scoped on
  `gym_id`. Accepting an invite is gated by possessing the random `token`
  (see `Matwork.Gyms.Membership`'s `:accept_invite` action), the same
  trust model this codebase already uses for magic-link sign-in.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Gyms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "invites"
    repo Matwork.Repo
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  actions do
    defaults [:read]

    create :create do
      accept [:email, :role]
      change Matwork.Gyms.Invite.Changes.GenerateToken
    end

    read :get_by_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(token == ^arg(:token))
    end

    update :mark_accepted do
      accept []
      change set_attribute(:accepted_at, expr(now()))
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end

    policy action(:read) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end

    # Token possession is the credential here, mirroring the existing
    # magic-link sign-in pattern in Matwork.Accounts.User — the invited
    # person does not have a Membership yet, so an ActiveMember check
    # can never pass for them.
    policy action(:get_by_token) do
      authorize_if always()
    end

    policy action(:mark_accepted) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      constraints one_of: [:owner, :instructor, :student]
      allow_nil? false
      public? true
    end

    attribute :token, :string do
      allow_nil? false
      writable? false
      public? true
    end

    attribute :accepted_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :gym, Matwork.Gyms.Gym do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_token, [:token]
  end
end
```

- [ ] **Step 3: Register the resource and its code interfaces**

Modify `lib/matwork/gyms.ex`, adding a third resource block:

```elixir
    resource Matwork.Gyms.Invite do
      define :create_invite, action: :create, args: [:email, :role]
      define :get_invite_by_token, action: :get_by_token, args: [:token]
      define :mark_invite_accepted, action: :mark_accepted
    end
```

so the full `resources do ... end` block reads:

```elixir
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
    end

    resource Matwork.Gyms.Invite do
      define :create_invite, action: :create, args: [:email, :role]
      define :get_invite_by_token, action: :get_by_token, args: [:token]
      define :mark_invite_accepted, action: :mark_accepted
    end
  end
```

- [ ] **Step 4: Run codegen and migrate**

```bash
mix ash.codegen add_invite
mix ash.migrate
```

Expected: a migration creating `invites` with `id`, `gym_id`, `email`, `role`, `token`, `accepted_at`, timestamps, an FK to `gyms`, and the tenant-scoped unique index on `(gym_id, token)`.

- [ ] **Step 5: Add an `invite` generator**

Modify `test/support/generator.ex`, adding after `membership/1`:

```elixir
  def invite(opts \\ []) do
    {owning_gym, opts} = Keyword.pop(opts, :gym)
    {inviter, opts} = Keyword.pop(opts, :inviter)

    owning_gym = owning_gym || generate(gym())
    inviter = inviter || owning_gym.owner_id |> then(&%Matwork.Accounts.User{id: &1})

    changeset_generator(
      Matwork.Gyms.Invite,
      :create,
      defaults: [
        email: sequence(:invite_email, &"student-#{&1}@example.com"),
        role: :student
      ],
      actor: inviter,
      tenant: owning_gym.id,
      overrides: opts
    )
  end
```

- [ ] **Step 6: Write the failing tests**

Create `test/matwork/gyms/invite_test.exs`:

```elixir
defmodule Matwork.Gyms.InviteTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Gyms

  describe "create" do
    test "an owner can invite a student by email" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      invite =
        Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      assert invite.email == Ash.CiString.new("student@example.com")
      refute is_nil(invite.token)
      assert is_nil(invite.accepted_at)
    end

    test "an instructor can invite a student by email" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      invite =
        Gyms.create_invite!("student@example.com", :student, actor: instructor, tenant: gym.id)

      assert invite.email == Ash.CiString.new("student@example.com")
    end

    test "a student cannot invite anyone" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.create_invite!("student@example.com", :student, actor: student, tenant: gym.id)
      end
    end

    test "someone outside the gym cannot invite anyone" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      outsider = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.create_invite!("student@example.com", :student, actor: outsider, tenant: gym.id)
      end
    end
  end

  describe "get_by_token" do
    test "anyone can look up an invite by its exact token, without a membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      stranger = generate(user())

      assert {:ok, found} =
               Gyms.get_invite_by_token(invite.token, actor: stranger, tenant: gym.id)

      assert found.id == invite.id
    end

    test "an incorrect token is not found" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      stranger = generate(user())

      assert {:error, %Ash.Error.Invalid{}} =
               Gyms.get_invite_by_token("not-a-real-token", actor: stranger, tenant: gym.id)
    end
  end

  describe "read (listing invites)" do
    test "an owner can list outstanding invites" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      generate(invite(gym: gym, inviter: owner))

      invites = Gyms.list_invites!(actor: owner, tenant: gym.id)

      assert length(invites) == 1
    end

    test "a student cannot list invites" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      generate(invite(gym: gym, inviter: owner))

      invites = Gyms.list_invites!(actor: student, tenant: gym.id)

      assert invites == []
    end
  end
end
```

This references `Gyms.list_invites!/1`, which doesn't exist yet — add it to the `Invite` code interface block in `lib/matwork/gyms.ex` from Step 3 above:

```elixir
    resource Matwork.Gyms.Invite do
      define :create_invite, action: :create, args: [:email, :role]
      define :get_invite_by_token, action: :get_by_token, args: [:token]
      define :mark_invite_accepted, action: :mark_accepted
      define :list_invites, action: :read
    end
```

- [ ] **Step 7: Run the tests and verify they pass**

```bash
mix test test/matwork/gyms/invite_test.exs
```

Expected: `8 tests, 0 failures`.

- [ ] **Step 8: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add lib/matwork/gyms/invite.ex lib/matwork/gyms/invite/changes/generate_token.ex \
  lib/matwork/gyms.ex test/support/generator.ex test/matwork/gyms/invite_test.exs \
  priv/repo/migrations/ priv/resource_snapshots/
git commit -m "Add Invite resource with token-based acceptance and roster-manager policies"
```

---

### Task 5: `Membership.accept_invite` — tie `Invite` and `Membership` together

**Files:**
- Create: `lib/matwork/gyms/membership/changes/accept_invite.ex`
- Modify: `lib/matwork/gyms/membership.ex`
- Modify: `lib/matwork/gyms.ex`
- Test: `test/matwork/gyms/membership_test.exs`

**Interfaces:**
- Consumes: `Matwork.Gyms.get_invite_by_token/2`, `Matwork.Gyms.mark_invite_accepted/2` (Task 4).
- Produces: `Matwork.Gyms.accept_invite!(token, opts)` — this is the last piece of the "invite → join" flow; a future LiveView session will call this directly.

No schema changes — no `mix ash.codegen` needed.

- [ ] **Step 1: Write the change module**

Create `lib/matwork/gyms/membership/changes/accept_invite.ex`:

```elixir
defmodule Matwork.Gyms.Membership.Changes.AcceptInvite do
  @moduledoc """
  Looks up the Invite by its token (in the current tenant), and if it's
  valid and unused, sets this Membership's user_id/role from it and marks
  the Invite accepted. Upserts on the `unique_user_per_gym` identity, so a
  previously-removed member re-accepting an invite is reactivated.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    token = Ash.Changeset.get_argument(changeset, :token)
    tenant = changeset.tenant
    actor = context.actor

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      case Matwork.Gyms.get_invite_by_token(token, actor: actor, tenant: tenant) do
        {:ok, %{accepted_at: nil} = invite} ->
          changeset
          |> Ash.Changeset.force_change_attribute(:user_id, actor.id)
          |> Ash.Changeset.force_change_attribute(:role, invite.role)
          |> Ash.Changeset.force_change_attribute(:status, :active)
          |> Ash.Changeset.put_context(:invite, invite)

        {:ok, _already_accepted} ->
          Ash.Changeset.add_error(changeset,
            field: :token,
            message: "invite has already been accepted"
          )

        {:error, _not_found} ->
          Ash.Changeset.add_error(changeset, field: :token, message: "invalid invite token")
      end
    end)
    |> Ash.Changeset.after_action(fn changeset, membership ->
      case changeset.context[:invite] do
        nil ->
          {:ok, membership}

        invite ->
          case Matwork.Gyms.mark_invite_accepted(invite, actor: actor, tenant: tenant) do
            {:ok, _invite} -> {:ok, membership}
            {:error, error} -> {:error, error}
          end
      end
    end)
  end
end
```

- [ ] **Step 2: Add the `:accept_invite` action to `Membership`**

Modify `lib/matwork/gyms/membership.ex`, changing:

```elixir
    update :remove do
      accept []
      change set_attribute(:status, :removed)
    end
  end

  policies do
    policy action(:create_owner) do
      authorize_if expr(gym.owner_id == ^actor(:id))
    end

    policy action_type(:read) do
      authorize_if Matwork.Gyms.Checks.ActiveMember
    end

    policy action(:remove) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end
  end
```

to:

```elixir
    update :remove do
      accept []
      change set_attribute(:status, :removed)
    end

    create :accept_invite do
      argument :token, :string do
        allow_nil? false
      end

      upsert? true
      upsert_identity :unique_user_per_gym
      upsert_fields [:role, :status]

      change Matwork.Gyms.Membership.Changes.AcceptInvite
    end
  end

  policies do
    policy action(:create_owner) do
      authorize_if expr(gym.owner_id == ^actor(:id))
    end

    policy action_type(:read) do
      authorize_if Matwork.Gyms.Checks.ActiveMember
    end

    policy action(:remove) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end

    # Mirrors Invite's :get_by_token / :mark_accepted policies: token
    # possession is the credential, the same trust model as magic-link
    # sign-in. The actor accepting an invite has no Membership yet, so
    # an ActiveMember check could never pass for them.
    policy action(:accept_invite) do
      authorize_if actor_present()
    end
  end
```

- [ ] **Step 3: Add the `accept_invite` code interface**

Modify `lib/matwork/gyms.ex`, changing the `Membership` resource block from:

```elixir
    resource Matwork.Gyms.Membership do
      define :create_owner_membership, action: :create_owner, args: [:user_id]
      define :remove_membership, action: :remove
      define :list_memberships, action: :read
    end
```

to:

```elixir
    resource Matwork.Gyms.Membership do
      define :create_owner_membership, action: :create_owner, args: [:user_id]
      define :remove_membership, action: :remove
      define :list_memberships, action: :read
      define :accept_invite, action: :accept_invite, args: [:token]
    end
```

- [ ] **Step 4: Write the failing tests**

Modify `test/matwork/gyms/membership_test.exs`, adding a new describe block:

```elixir
  describe "accept_invite" do
    test "a logged-in user can accept a valid invite and becomes an active member" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      student = generate(user())

      membership =
        Gyms.accept_invite!(invite.token, actor: student, tenant: gym.id)

      assert membership.role == :student
      assert membership.status == :active
      assert membership.user_id == student.id

      accepted_invite = Gyms.get_invite_by_token!(invite.token, actor: student, tenant: gym.id)
      refute is_nil(accepted_invite.accepted_at)
    end

    test "an already-accepted invite cannot be accepted again" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      first_student = generate(user())
      Gyms.accept_invite!(invite.token, actor: first_student, tenant: gym.id)

      second_student = generate(user())

      assert_raise Ash.Error.Invalid, fn ->
        Gyms.accept_invite!(invite.token, actor: second_student, tenant: gym.id)
      end
    end

    test "an invalid token cannot be accepted" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())

      assert_raise Ash.Error.Invalid, fn ->
        Gyms.accept_invite!("not-a-real-token", actor: student, tenant: gym.id)
      end
    end

    test "no actor cannot accept an invite" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.accept_invite!(invite.token, actor: nil, tenant: gym.id)
      end
    end

    test "accepting an invite reactivates a previously-removed membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      membership = generate(membership(gym: gym, user: student, role: :student))
      Gyms.remove_membership!(membership, actor: owner, tenant: gym.id)

      invite =
        Gyms.create_invite!(
          Ash.CiString.value(student.email),
          :instructor,
          actor: owner,
          tenant: gym.id
        )

      reactivated = Gyms.accept_invite!(invite.token, actor: student, tenant: gym.id)

      assert reactivated.id == membership.id
      assert reactivated.status == :active
      assert reactivated.role == :instructor
    end
  end
```

- [ ] **Step 5: Run the tests and verify they pass**

```bash
mix test test/matwork/gyms/membership_test.exs
```

Expected: `12 tests, 0 failures`.

- [ ] **Step 6: Format, lint, full suite**

```bash
mix format
mix credo --strict
mix test
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/matwork/gyms/membership.ex lib/matwork/gyms/membership/changes/accept_invite.ex \
  lib/matwork/gyms.ex test/matwork/gyms/membership_test.exs
git commit -m "Add Membership.accept_invite tying Invite acceptance to roster membership"
```

---

## After this session

Demoable end state: from an ExUnit test (or `iex -S mix`), you can create a gym as any authenticated user (auto-becoming its owner with an active `Membership`), have that owner (or an instructor) invite a student by email, and have any authenticated user redeem that invite's token into an active student `Membership` — with tenancy isolation and role-based deny paths tested throughout.

Not in this session, deliberately: the `/g/:slug` router scope, the tenant-resolution plug/`on_mount` hook, LiveViews for any of this, and the Fly deploy pipeline. Per `design.md`'s Milestone 0 demo ("student signs in via magic link and sees the gym's empty home page"), those are the natural next session — they consume the code interfaces built here (`get_gym_by_slug`, `accept_invite`) rather than reaching into `Ash` directly, per the code-interface iron rule.
