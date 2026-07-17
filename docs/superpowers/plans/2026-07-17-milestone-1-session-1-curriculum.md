# Milestone 1 · Session 1 — Curriculum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the instructor-facing curriculum authoring slice of Milestone 1 — a `Course → CourseSection → Lesson` resource tree with instructor-gated CRUD, course publish/archive, `free_preview` lesson flag, positional ordering, and a single-page course-builder LiveView. No video yet.

**Architecture:** A new tenant-scoped `Matwork.Curriculum` Ash domain holds three resources. Write actions are gated by a shared `ManagesCurriculum` simple check (active owner/instructor in the tenant); reads are gated by per-resource filter checks that show drafts only to curriculum managers and published courses to any active member. Ordering is a plain integer `position`; new rows append (max+1) via plain domain functions, and reordering swaps positions with a neighbor. The builder LiveView drives everything through named domain code interfaces and plain domain functions — never raw `Ash` queries — passing `actor:` and `tenant:` resolved by the existing `MatworkWeb.GymLiveAuth` `on_mount` hook.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8 LiveView, Ash 3.x + `ash_postgres`, `AshPhoenix`, Tailwind/daisyUI, ExUnit + `Ash.Generator`.

**Spec:** `docs/superpowers/specs/2026-07-16-milestone-1-curriculum-video-design.md` (§2.1 resources, §3.1–3.2 authorization, §4 Session 1). Read it before starting.

## Global Constraints

Copied verbatim from `CLAUDE.md` and the spec — every task implicitly includes these:

- **Consult the `ash-framework` skill before making any domain change** (project rule). Also `mix usage_rules.docs Ash.<Module>` when unsure of an Ash API.
- **Multitenancy:** `Course`, `CourseSection`, `Lesson` are attribute-multitenant on `gym_id` — every one MUST have the `multitenancy do strategy :attribute; attribute :gym_id end` block. Every Ash call on them passes both `actor:` and `tenant:`.
- **Primary keys are `uuid_primary_key :id`.** ⚠️ The spec/design doc §4 says `bigserial`, but every existing M0 resource (`Gym`, `Membership`, `Invite`, `User`) uses UUID. **This plan follows the code, not the doc** — matching the existing resources matters more than the doc's POC-era ID note. Flag this reconciliation in the Session-1 recap.
- **Authorization lives in resource policies**, never in LiveViews. LiveViews call domain code interfaces / plain domain functions only — no raw `Ash.read!/2`.
- **No `authorize?: false`** outside seeds, migrations, and system-actor webhook jobs. (Session 1 needs none.)
- **`StalwartUI` components** depend only on `Phoenix.Component`, Tailwind/daisyUI, and their own hooks — never on a resource, domain, or route helper. They take plain assigns. Update `COMPONENTS.md` when you add one.
- **Migrations:** after each resource change run `mix ash.codegen <descriptive_name>`; never hand-write migrations for Ash-managed tables.
- **Money:** N/A this session (no money involved).
- **Before every commit:** `mix format`, `mix credo --strict`, `mix test` — all green.
- **Every policy gets allow AND deny tests; test tenant isolation explicitly** (a user in gym A must not read/mutate gym B's rows).

---

## File Structure

**Create:**

- `lib/matwork/curriculum.ex` — the `Matwork.Curriculum` Ash domain: code interfaces + plain ordering/reorder functions.
- `lib/matwork/curriculum/course.ex` — `Course` resource.
- `lib/matwork/curriculum/course_section.ex` — `CourseSection` resource.
- `lib/matwork/curriculum/lesson.ex` — `Lesson` resource.
- `lib/matwork/curriculum/checks/manages_curriculum.ex` — write-gating simple check (shared).
- `lib/matwork/curriculum/checks/course_visible.ex` — `Course` read filter check.
- `lib/matwork/curriculum/checks/section_visible.ex` — `CourseSection` read filter check.
- `lib/matwork/curriculum/checks/lesson_visible.ex` — `Lesson` read filter check.
- `lib/stalwart_ui/curriculum_tree.ex` — `StalwartUI.CurriculumTree` component.
- `lib/matwork_web/live/course_index_live.ex` — `/g/:slug/courses` list + create.
- `lib/matwork_web/live/course_builder_live.ex` — `/g/:slug/courses/:id/edit` builder.
- `test/matwork/curriculum/course_test.exs`
- `test/matwork/curriculum/course_section_test.exs`
- `test/matwork/curriculum/lesson_test.exs`
- `test/stalwart_ui/curriculum_tree_test.exs`
- `test/matwork_web/live/course_index_live_test.exs`
- `test/matwork_web/live/course_builder_live_test.exs`

**Modify:**

- `config/config.exs:69` — add `Matwork.Curriculum` to `ash_domains`.
- `test/support/generator.ex` — add `course/1`, `section/1`, `lesson/1` seed generators.
- `lib/matwork_web/router.ex` — add three routes under the existing `:gym_routes` live session.
- `COMPONENTS.md` — add the `CurriculumTree` entry.

**Task → file map:** Task 1 covers the domain skeleton + `Course` + `ManagesCurriculum` + `CourseVisible` + config + generator. Task 2 adds `CourseSection` + `SectionVisible` + ordering functions. Task 3 adds `Lesson` + `LessonVisible`. Task 4 is the `CurriculumTree` component. Task 5 is the index LiveView. Task 6 is the builder LiveView.

---

## Task 1: Curriculum domain + `Course` resource + write/read policies

**Files:**
- Create: `lib/matwork/curriculum/checks/manages_curriculum.ex`, `lib/matwork/curriculum/checks/course_visible.ex`, `lib/matwork/curriculum/course.ex`, `lib/matwork/curriculum.ex`
- Modify: `config/config.exs:69`, `test/support/generator.ex`
- Test: `test/matwork/curriculum/course_test.exs`

**Interfaces:**
- Produces (used by Tasks 2, 3, 5, 6):
  - Check `Matwork.Curriculum.Checks.ManagesCurriculum` — `use Ash.Policy.SimpleCheck`; matches when actor has an active `:owner`/`:instructor` membership in the tenant.
  - Domain `Matwork.Curriculum` code interfaces: `create_course(title, params \\ %{}, opts)`, `get_course(id, opts)`, `list_courses(opts)`, `update_course(course, params \\ %{}, opts)`, `publish_course(course, opts)`, `archive_course(course, opts)`, `unarchive_course(course, opts)` (+ `!` variants).
  - Plain domain function `add_course(gym_id, title, opts) :: {:ok, Course.t()} | {:error, term}` — appends at next position.
  - Test generator `course(opts)` — `seed_generator` for `Matwork.Curriculum.Course`, accepts `gym:` (a `%Gym{}`) and attribute overrides.

- [ ] **Step 1: Register the domain in config**

Modify `config/config.exs` line 69:

```elixir
  ash_domains: [Matwork.Accounts, Matwork.Gyms, Matwork.Curriculum],
```

- [ ] **Step 2: Write the `ManagesCurriculum` check**

This mirrors `lib/matwork/gyms/checks/active_member.ex` but fixes the roles to curriculum managers.

Create `lib/matwork/curriculum/checks/manages_curriculum.ex`:

```elixir
defmodule Matwork.Curriculum.Checks.ManagesCurriculum do
  @moduledoc """
  Policy check: does the actor hold an active `:owner` or `:instructor`
  Membership in the tenant the current request is scoped to? Gates every
  write action on the Curriculum resources.

  Mirrors `Matwork.Gyms.Checks.ActiveMember`, narrowed to the two roles
  that may build curriculum.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  def describe(_opts) do
    "actor has an active owner/instructor membership in this gym"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    tenant = context.subject.tenant

    Matwork.Gyms.Membership
    |> Ash.Query.filter(
      user_id == ^actor.id and status == :active and role in [:owner, :instructor]
    )
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end
end
```

- [ ] **Step 3: Write the `CourseVisible` read filter check**

Mirrors `lib/matwork/gyms/checks/roster_visible.ex` (a `FilterCheck`).

Create `lib/matwork/curriculum/checks/course_visible.ex`:

```elixir
defmodule Matwork.Curriculum.Checks.CourseVisible do
  @moduledoc """
  Filter check for `Course`'s `:read` action. An actor may read a course if:

    * they manage curriculum in this gym (active owner/instructor) — sees all
      courses regardless of status; OR
    * the course is `:published` AND they hold any active membership in this gym.

  Non-members see nothing (in addition to Ash's tenant isolation).
  """
  use Ash.Policy.FilterCheck

  def describe(_opts) do
    "course is published (for active members), or actor manages curriculum in this gym"
  end

  def filter(_actor, _authorizer, _opts) do
    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and
          role in [:owner, :instructor] and gym_id == ^tenant()
      ) or
        (status == :published and
           exists(
             Matwork.Gyms.Membership,
             user_id == ^actor(:id) and status == :active and gym_id == ^tenant()
           ))
    )
  end
end
```

- [ ] **Step 4: Write the `Course` resource**

Create `lib/matwork/curriculum/course.ex` (structure copied from `lib/matwork/gyms/invite.ex`):

```elixir
defmodule Matwork.Curriculum.Course do
  @moduledoc """
  A gym's course: the root of the curriculum tree. Tenant-scoped on `gym_id`.
  `status` drives student visibility (see `Checks.CourseVisible`); ordering is
  a plain integer `position`.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "courses"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :description, :position]
    end

    update :update do
      accept [:title, :description]
    end

    update :set_position do
      accept [:position]
    end

    update :publish do
      accept []
      change set_attribute(:status, :published)
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    update :unarchive do
      accept []
      change set_attribute(:status, :draft)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Matwork.Curriculum.Checks.CourseVisible
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Matwork.Curriculum.Checks.ManagesCurriculum
    end
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
      default :draft
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      default 0
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
  end
end
```

- [ ] **Step 5: Write the `Matwork.Curriculum` domain**

Create `lib/matwork/curriculum.ex`. The `add_course/3` helper computes the next append position with a normal authorized read (the actor is a curriculum manager, so `CourseVisible` lets them read every course).

```elixir
defmodule Matwork.Curriculum do
  @moduledoc "The Curriculum domain: courses, sections, and lessons."
  use Ash.Domain,
    otp_app: :matwork,
    extensions: [AshPhoenix]

  require Ash.Query

  resources do
    resource Matwork.Curriculum.Course do
      define :create_course, action: :create, args: [:title]
      define :get_course, action: :read, get_by: [:id]
      define :list_courses, action: :read
      define :update_course, action: :update
      define :set_course_position, action: :set_position
      define :publish_course, action: :publish
      define :archive_course, action: :archive
      define :unarchive_course, action: :unarchive
    end
  end

  @doc """
  Create a course at the end of the gym's course list (next `position`).
  `opts` must include `:actor` and `:tenant`.
  """
  def add_course(_gym_id, title, opts) do
    position = next_position(Matwork.Curriculum.Course, [], opts)
    create_course(title, %{position: position}, opts)
  end

  # Returns max(position)+1 among the rows matching `filter` (a keyword filter
  # like `[course_id: id]`), or 0 when there are none. Reads with the caller's
  # actor/tenant — curriculum managers can read all rows.
  @doc false
  def next_position(resource, filter, opts) do
    query =
      resource
      |> Ash.Query.filter(^filter)
      |> Ash.Query.sort(position: :desc)
      |> Ash.Query.limit(1)

    case Ash.read!(query, opts) do
      [%{position: position}] -> position + 1
      [] -> 0
    end
  end
end
```

- [ ] **Step 6: Add the `course` test generator**

In `test/support/generator.ex`, add after the `invite/1` function (inside the module):

```elixir
  def course(opts \\ []) do
    {owning_gym, opts} = Keyword.pop(opts, :gym)
    owning_gym = owning_gym || generate(gym())

    seed_generator(
      %Matwork.Curriculum.Course{
        gym_id: owning_gym.id,
        title: sequence(:course_title, &"Course #{&1}"),
        status: :draft,
        position: 0
      },
      overrides: opts
    )
  end
```

- [ ] **Step 7: Generate the migration**

Run: `mix ash.codegen create_courses`
Expected: creates a migration under `priv/repo/migrations/` for the `courses` table. Then run `mix ecto.migrate` and expect it to apply cleanly.

- [ ] **Step 8: Write the failing tests**

Create `test/matwork/curriculum/course_test.exs`:

```elixir
defmodule Matwork.Curriculum.CourseTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Curriculum

  describe "create / update (write gating)" do
    test "an owner can create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      {:ok, course} = Curriculum.add_course(gym.id, "Half Guard", actor: owner, tenant: gym.id)

      assert course.title == "Half Guard"
      assert course.status == :draft
      assert course.position == 0
    end

    test "an instructor can create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      {:ok, course} =
        Curriculum.add_course(gym.id, "Guard Passing", actor: instructor, tenant: gym.id)

      assert course.title == "Guard Passing"
    end

    test "a student cannot create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.add_course(gym.id, "Nope", actor: student, tenant: gym.id)
    end

    test "a non-member cannot create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      stranger = generate(user())

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.add_course(gym.id, "Nope", actor: stranger, tenant: gym.id)
    end

    test "add_course appends at the next position" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      {:ok, first} = Curriculum.add_course(gym.id, "One", actor: owner, tenant: gym.id)
      {:ok, second} = Curriculum.add_course(gym.id, "Two", actor: owner, tenant: gym.id)

      assert first.position == 0
      assert second.position == 1
    end
  end

  describe "publish / archive" do
    test "an owner can publish and archive a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course = generate(course(gym: gym))

      {:ok, published} = Curriculum.publish_course(course, actor: owner, tenant: gym.id)
      assert published.status == :published

      {:ok, archived} = Curriculum.archive_course(published, actor: owner, tenant: gym.id)
      assert archived.status == :archived
    end

    test "a student cannot publish a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      course = generate(course(gym: gym))

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.publish_course(course, actor: student, tenant: gym.id)
    end
  end

  describe "read (visibility)" do
    test "an instructor sees draft and published courses" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      generate(course(gym: gym, status: :draft))
      generate(course(gym: gym, status: :published))

      courses = Curriculum.list_courses!(actor: owner, tenant: gym.id)

      assert length(courses) == 2
    end

    test "a student sees only published courses" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      generate(course(gym: gym, status: :draft))
      published = generate(course(gym: gym, status: :published))

      courses = Curriculum.list_courses!(actor: student, tenant: gym.id)

      assert Enum.map(courses, & &1.id) == [published.id]
    end

    test "a non-member sees no courses" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      generate(course(gym: gym, status: :published))
      stranger = generate(user())

      assert Curriculum.list_courses!(actor: stranger, tenant: gym.id) == []
    end

    test "tenancy isolation: an instructor in gym A cannot read gym B's courses" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      generate(course(gym: gym_b, status: :published))

      assert Curriculum.list_courses!(actor: owner_a, tenant: gym_b.id) == []
    end
  end
end
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `mix test test/matwork/curriculum/course_test.exs`
Expected: all pass. (If a test fails first because the resource wasn't compiled yet, that confirms the red→green cycle; re-run after Steps 4–7.)

- [ ] **Step 10: Format, lint, commit**

```bash
mix format
mix credo --strict
git add config/config.exs lib/matwork/curriculum.ex lib/matwork/curriculum/ test/support/generator.ex test/matwork/curriculum/course_test.exs priv/repo/migrations
git commit -m "Add Curriculum domain and Course resource with policies"
```

---

## Task 2: `CourseSection` resource + ordering + reorder

**Files:**
- Create: `lib/matwork/curriculum/course_section.ex`, `lib/matwork/curriculum/checks/section_visible.ex`
- Modify: `lib/matwork/curriculum.ex` (add resource block + section functions), `test/support/generator.ex`
- Test: `test/matwork/curriculum/course_section_test.exs`

**Interfaces:**
- Consumes: `Matwork.Curriculum.Checks.ManagesCurriculum`, `Course` (Task 1); `Matwork.Curriculum.next_position/3`.
- Produces (used by Tasks 3, 6):
  - Code interfaces: `list_sections(opts)`, `update_section(section, params, opts)`, `set_section_position(section, params, opts)`, `destroy_section(section, opts)`, `create_section(course_id, title, params \\ %{}, opts)` (+ `!`).
  - Plain functions: `add_section(course, title, opts)`, `reorder_section(section, direction, opts)` where `direction` is `:up | :down` — returns `:ok`.
  - Generator `section(opts)` — `seed_generator` for `CourseSection`, accepts `course:` (a `%Course{}`).

- [ ] **Step 1: Write the `SectionVisible` read filter check**

Create `lib/matwork/curriculum/checks/section_visible.ex`. Same shape as `CourseVisible`, but the published branch checks the parent course's status via the `course` relationship.

```elixir
defmodule Matwork.Curriculum.Checks.SectionVisible do
  @moduledoc """
  Filter check for `CourseSection`'s `:read` action: readable if the actor
  manages curriculum in this gym, or the section's course is `:published` and
  the actor is any active member. Mirrors `Checks.CourseVisible`, reaching
  through the `course` relationship for the published branch.
  """
  use Ash.Policy.FilterCheck

  def describe(_opts) do
    "section's course is published (for active members), or actor manages curriculum in this gym"
  end

  def filter(_actor, _authorizer, _opts) do
    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and
          role in [:owner, :instructor] and gym_id == ^tenant()
      ) or
        (course.status == :published and
           exists(
             Matwork.Gyms.Membership,
             user_id == ^actor(:id) and status == :active and gym_id == ^tenant()
           ))
    )
  end
end
```

- [ ] **Step 2: Write the `CourseSection` resource**

Create `lib/matwork/curriculum/course_section.ex`:

```elixir
defmodule Matwork.Curriculum.CourseSection do
  @moduledoc """
  A section within a course: an ordered grouping of lessons. Tenant-scoped
  on `gym_id`.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "course_sections"
    repo Matwork.Repo

    references do
      reference :course, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:course_id, :title, :position]
    end

    update :update do
      accept [:title]
    end

    update :set_position do
      accept [:position]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Matwork.Curriculum.Checks.SectionVisible
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Matwork.Curriculum.Checks.ManagesCurriculum
    end
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      default 0
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

    belongs_to :course, Matwork.Curriculum.Course do
      allow_nil? false
      public? true
    end
  end
end
```

- [ ] **Step 3: Extend the domain with section interfaces + functions**

In `lib/matwork/curriculum.ex`, add inside the `resources do ... end` block:

```elixir
    resource Matwork.Curriculum.CourseSection do
      define :create_section, action: :create, args: [:course_id, :title]
      define :list_sections, action: :read
      define :update_section, action: :update
      define :set_section_position, action: :set_position
      define :destroy_section, action: :destroy
    end
```

And add these functions to the module body (after `add_course/3`):

```elixir
  @doc "Create a section at the end of its course. `opts` needs `:actor` and `:tenant`."
  def add_section(course, title, opts) do
    position = next_position(Matwork.Curriculum.CourseSection, [course_id: course.id], opts)

    create_section(
      course.id,
      title,
      %{position: position, gym_id: course.gym_id},
      opts
    )
  end

  @doc "Move a section one slot `:up` or `:down` among its course siblings."
  def reorder_section(section, direction, opts) do
    swap_position(
      Matwork.Curriculum.CourseSection,
      [course_id: section.course_id],
      section,
      direction,
      &set_section_position!/3,
      opts
    )
  end
```

Note: `create_section`'s action accepts `[:course_id, :title, :position]`, not `gym_id`. The tenant supplies `gym_id` automatically from `opts[:tenant]` — but because `gym_id` is a plain `belongs_to` attribute set by multitenancy, you do NOT pass it in the params map. Correct the call to omit `gym_id`:

```elixir
  def add_section(course, title, opts) do
    position = next_position(Matwork.Curriculum.CourseSection, [course_id: course.id], opts)
    create_section(course.id, title, %{position: position}, opts)
  end
```

Then add the shared swap helper (used by lessons too in Task 3) to the module body:

```elixir
  # Swap `record`'s position with its neighbor one slot in `direction`
  # (`:up`/`:down`) among the siblings matching `filter`. No-op at a boundary.
  # `set_position_fun` is the resource's `set_*_position!` code interface.
  @doc false
  def swap_position(resource, filter, record, direction, set_position_fun, opts) do
    siblings =
      resource
      |> Ash.Query.filter(^filter)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(opts)

    index = Enum.find_index(siblings, &(&1.id == record.id))
    target = index && index + delta(direction)

    if is_integer(target) and target >= 0 and target < length(siblings) do
      neighbor = Enum.at(siblings, target)
      set_position_fun.(record, %{position: neighbor.position}, opts)
      set_position_fun.(neighbor, %{position: record.position}, opts)
    end

    :ok
  end

  defp delta(:up), do: -1
  defp delta(:down), do: 1
```

- [ ] **Step 4: Add the `section` test generator**

In `test/support/generator.ex`, add:

```elixir
  def section(opts \\ []) do
    {owning_course, opts} = Keyword.pop(opts, :course)
    owning_course = owning_course || generate(course())

    seed_generator(
      %Matwork.Curriculum.CourseSection{
        gym_id: owning_course.gym_id,
        course_id: owning_course.id,
        title: sequence(:section_title, &"Section #{&1}"),
        position: 0
      },
      overrides: opts
    )
  end
```

- [ ] **Step 5: Generate the migration**

Run: `mix ash.codegen create_course_sections` then `mix ecto.migrate`
Expected: a migration for `course_sections` with a FK to `courses`; applies cleanly.

- [ ] **Step 6: Write the failing tests**

Create `test/matwork/curriculum/course_section_test.exs`:

```elixir
defmodule Matwork.Curriculum.CourseSectionTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Curriculum

  describe "add_section (write gating + ordering)" do
    test "an instructor can add sections, appended in order" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))
      course = generate(course(gym: gym))

      {:ok, a} = Curriculum.add_section(course, "Sweeps", actor: instructor, tenant: gym.id)
      {:ok, b} = Curriculum.add_section(course, "Submissions", actor: instructor, tenant: gym.id)

      assert a.position == 0
      assert b.position == 1
    end

    test "a student cannot add a section" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      course = generate(course(gym: gym))

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.add_section(course, "Nope", actor: student, tenant: gym.id)
    end
  end

  describe "reorder_section" do
    test "moving a section down swaps it with its successor" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course = generate(course(gym: gym))
      first = generate(section(course: course, position: 0))
      second = generate(section(course: course, position: 1))

      :ok = Curriculum.reorder_section(first, :down, actor: owner, tenant: gym.id)

      ordered =
        Curriculum.list_sections!(actor: owner, tenant: gym.id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert ordered == [second.id, first.id]
    end

    test "moving the first section up is a no-op" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course = generate(course(gym: gym))
      first = generate(section(course: course, position: 0))
      second = generate(section(course: course, position: 1))

      :ok = Curriculum.reorder_section(first, :up, actor: owner, tenant: gym.id)

      ordered =
        Curriculum.list_sections!(actor: owner, tenant: gym.id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert ordered == [first.id, second.id]
    end
  end

  describe "read visibility" do
    test "a student sees sections of a published course but not a draft one" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      published = generate(course(gym: gym, status: :published))
      draft = generate(course(gym: gym, status: :draft))
      visible = generate(section(course: published))
      generate(section(course: draft))

      ids =
        Curriculum.list_sections!(actor: student, tenant: gym.id)
        |> Enum.map(& &1.id)

      assert ids == [visible.id]
    end
  end
end
```

- [ ] **Step 7: Run tests**

Run: `mix test test/matwork/curriculum/course_section_test.exs`
Expected: all pass.

- [ ] **Step 8: Format, lint, commit**

```bash
mix format
mix credo --strict
git add lib/matwork/curriculum.ex lib/matwork/curriculum/course_section.ex lib/matwork/curriculum/checks/section_visible.ex test/support/generator.ex test/matwork/curriculum/course_section_test.exs priv/repo/migrations
git commit -m "Add CourseSection resource with ordering and reorder"
```

---

## Task 3: `Lesson` resource + `free_preview` + ordering

**Files:**
- Create: `lib/matwork/curriculum/lesson.ex`, `lib/matwork/curriculum/checks/lesson_visible.ex`
- Modify: `lib/matwork/curriculum.ex`, `test/support/generator.ex`
- Test: `test/matwork/curriculum/lesson_test.exs`

**Interfaces:**
- Consumes: `ManagesCurriculum`, `CourseSection`, `next_position/3`, `swap_position/6` (Tasks 1–2).
- Produces (used by Task 6):
  - Code interfaces: `list_lessons(opts)`, `update_lesson(lesson, params, opts)`, `set_lesson_position(lesson, params, opts)`, `destroy_lesson(lesson, opts)`, `create_lesson(section_id, title, params \\ %{}, opts)` (+ `!`).
  - Plain functions: `add_lesson(section, title, opts)`, `reorder_lesson(lesson, direction, opts)`, `set_lesson_preview(lesson, bool, opts)`.
  - Generator `lesson(opts)` — accepts `section:` (a `%CourseSection{}`).

- [ ] **Step 1: Write the `LessonVisible` read filter check**

Create `lib/matwork/curriculum/checks/lesson_visible.ex`. Published branch reaches through `section.course.status`. (`free_preview` does NOT affect read — it only gates playback in Session 3.)

```elixir
defmodule Matwork.Curriculum.Checks.LessonVisible do
  @moduledoc """
  Filter check for `Lesson`'s `:read` action: readable if the actor manages
  curriculum in this gym, or the lesson's course is `:published` and the actor
  is any active member. `free_preview` is irrelevant here — it gates playback
  (Session 3), not whether a lesson appears in the tree.
  """
  use Ash.Policy.FilterCheck

  def describe(_opts) do
    "lesson's course is published (for active members), or actor manages curriculum in this gym"
  end

  def filter(_actor, _authorizer, _opts) do
    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and
          role in [:owner, :instructor] and gym_id == ^tenant()
      ) or
        (section.course.status == :published and
           exists(
             Matwork.Gyms.Membership,
             user_id == ^actor(:id) and status == :active and gym_id == ^tenant()
           ))
    )
  end
end
```

- [ ] **Step 2: Write the `Lesson` resource**

Create `lib/matwork/curriculum/lesson.ex`. No `video_id` yet — that FK arrives in Session 2 (Media), because the `Video` table does not exist yet.

```elixir
defmodule Matwork.Curriculum.Lesson do
  @moduledoc """
  A lesson within a section. Tenant-scoped on `gym_id`. `free_preview` marks a
  lesson as watchable without payment (playback gating lands in Session 3).
  A `video_id` relationship is added in Session 2 with the Media domain.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lessons"
    repo Matwork.Repo

    references do
      reference :section, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:section_id, :title, :description, :free_preview, :position]
    end

    update :update do
      accept [:title, :description, :free_preview]
    end

    update :set_position do
      accept [:position]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Matwork.Curriculum.Checks.LessonVisible
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Matwork.Curriculum.Checks.ManagesCurriculum
    end
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :free_preview, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      default 0
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

    belongs_to :section, Matwork.Curriculum.CourseSection do
      allow_nil? false
      public? true
    end
  end
end
```

- [ ] **Step 3: Extend the domain with lesson interfaces + functions**

In `lib/matwork/curriculum.ex`, add inside `resources do ... end`:

```elixir
    resource Matwork.Curriculum.Lesson do
      define :create_lesson, action: :create, args: [:section_id, :title]
      define :list_lessons, action: :read
      define :update_lesson, action: :update
      define :set_lesson_position, action: :set_position
      define :destroy_lesson, action: :destroy
    end
```

And add to the module body:

```elixir
  @doc "Create a lesson at the end of its section."
  def add_lesson(section, title, opts) do
    position = next_position(Matwork.Curriculum.Lesson, [section_id: section.id], opts)
    create_lesson(section.id, title, %{position: position}, opts)
  end

  @doc "Toggle/set a lesson's free-preview flag."
  def set_lesson_preview(lesson, value, opts) when is_boolean(value) do
    update_lesson(lesson, %{free_preview: value}, opts)
  end

  @doc "Move a lesson one slot `:up`/`:down` among its section siblings."
  def reorder_lesson(lesson, direction, opts) do
    swap_position(
      Matwork.Curriculum.Lesson,
      [section_id: lesson.section_id],
      lesson,
      direction,
      &set_lesson_position!/3,
      opts
    )
  end
```

- [ ] **Step 4: Add the `lesson` test generator**

In `test/support/generator.ex`, add:

```elixir
  def lesson(opts \\ []) do
    {owning_section, opts} = Keyword.pop(opts, :section)
    owning_section = owning_section || generate(section())

    seed_generator(
      %Matwork.Curriculum.Lesson{
        gym_id: owning_section.gym_id,
        section_id: owning_section.id,
        title: sequence(:lesson_title, &"Lesson #{&1}"),
        free_preview: false,
        position: 0
      },
      overrides: opts
    )
  end
```

- [ ] **Step 5: Generate the migration**

Run: `mix ash.codegen create_lessons` then `mix ecto.migrate`
Expected: a migration for `lessons` with a FK to `course_sections`; applies cleanly.

- [ ] **Step 6: Write the failing tests**

Create `test/matwork/curriculum/lesson_test.exs`:

```elixir
defmodule Matwork.Curriculum.LessonTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Curriculum

  describe "add_lesson (write gating + ordering)" do
    test "an owner can add lessons, appended in order, defaulting to not-preview" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course = generate(course(gym: gym))
      section = generate(section(course: course))

      {:ok, a} = Curriculum.add_lesson(section, "Old-school sweep", actor: owner, tenant: gym.id)
      {:ok, b} = Curriculum.add_lesson(section, "Far-side underhook", actor: owner, tenant: gym.id)

      assert a.position == 0
      assert b.position == 1
      refute a.free_preview
    end

    test "a student cannot add a lesson" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      section = generate(section(course: generate(course(gym: gym))))

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.add_lesson(section, "Nope", actor: student, tenant: gym.id)
    end
  end

  describe "set_lesson_preview" do
    test "an instructor can mark a lesson as free preview" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      section = generate(section(course: generate(course(gym: gym))))
      lesson = generate(lesson(section: section))

      {:ok, updated} = Curriculum.set_lesson_preview(lesson, true, actor: owner, tenant: gym.id)

      assert updated.free_preview
    end
  end

  describe "reorder_lesson" do
    test "moving a lesson down swaps it with its successor" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      section = generate(section(course: generate(course(gym: gym))))
      first = generate(lesson(section: section, position: 0))
      second = generate(lesson(section: section, position: 1))

      :ok = Curriculum.reorder_lesson(first, :down, actor: owner, tenant: gym.id)

      ordered =
        Curriculum.list_lessons!(actor: owner, tenant: gym.id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert ordered == [second.id, first.id]
    end
  end

  describe "read visibility" do
    test "a student sees lessons of a published course only" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      pub_section = generate(section(course: generate(course(gym: gym, status: :published))))
      draft_section = generate(section(course: generate(course(gym: gym, status: :draft))))
      visible = generate(lesson(section: pub_section))
      generate(lesson(section: draft_section))

      ids = Curriculum.list_lessons!(actor: student, tenant: gym.id) |> Enum.map(& &1.id)

      assert ids == [visible.id]
    end
  end
end
```

- [ ] **Step 7: Run tests**

Run: `mix test test/matwork/curriculum/lesson_test.exs`
Expected: all pass.

- [ ] **Step 8: Format, lint, commit**

```bash
mix format
mix credo --strict
git add lib/matwork/curriculum.ex lib/matwork/curriculum/lesson.ex lib/matwork/curriculum/checks/lesson_visible.ex test/support/generator.ex test/matwork/curriculum/lesson_test.exs priv/repo/migrations
git commit -m "Add Lesson resource with free_preview and ordering"
```

---

## Task 4: `StalwartUI.CurriculumTree` component

Renders the course tree with author controls. Plain assigns + parent-supplied event names only — no resource/domain/route references (mirrors `StalwartUI.RosterTable` / `InviteForm`). Every mutating control is a small always-visible `<form>` or button emitting a parent event with `phx-value-*` ids.

**Files:**
- Create: `lib/stalwart_ui/curriculum_tree.ex`
- Modify: `COMPONENTS.md`
- Test: `test/stalwart_ui/curriculum_tree_test.exs`

**Interfaces:**
- Produces (used by Task 6): `StalwartUI.CurriculumTree.curriculum_tree/1`. Assigns:
  - `sections` (required) — list of maps, each `%{id, title, lessons: [%{id, title, free_preview}]}`, pre-sorted by the caller.
  - `on_add_section`, `on_rename_section`, `on_delete_section`, `on_move_section`, `on_add_lesson`, `on_rename_lesson`, `on_delete_lesson`, `on_move_lesson`, `on_toggle_preview` — phx event-name strings (all have defaults).
  - Move events carry `phx-value-id` and `phx-value-direction` (`"up"`/`"down"`). Add/rename forms submit `%{"id" => ..., "title" => ...}` (rename/add-lesson) or `%{"title" => ...}` (add-section). Toggle/delete carry `phx-value-id`.

- [ ] **Step 1: Write the failing component test**

Create `test/stalwart_ui/curriculum_tree_test.exs` (mirrors `test/stalwart_ui/roster_table_test.exs` — `render_component/2`):

```elixir
defmodule StalwartUI.CurriculumTreeTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import StalwartUI.CurriculumTree

  defp tree(assigns) do
    render_component(&curriculum_tree/1, assigns)
  end

  test "renders sections and their lessons" do
    html =
      tree(%{
        sections: [
          %{
            id: "s1",
            title: "Sweeps",
            lessons: [%{id: "l1", title: "Old-school sweep", free_preview: true}]
          }
        ]
      })

    assert html =~ "Sweeps"
    assert html =~ "Old-school sweep"
  end

  test "marks free-preview lessons" do
    html =
      tree(%{
        sections: [
          %{id: "s1", title: "Sweeps", lessons: [%{id: "l1", title: "L", free_preview: true}]}
        ]
      })

    assert html =~ "Preview"
  end

  test "renders an empty-state when there are no sections" do
    assert tree(%{sections: []}) =~ "No sections yet"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/stalwart_ui/curriculum_tree_test.exs`
Expected: FAIL — `StalwartUI.CurriculumTree` is undefined.

- [ ] **Step 3: Write the component**

Create `lib/stalwart_ui/curriculum_tree.ex`:

```elixir
defmodule StalwartUI.CurriculumTree do
  @moduledoc """
  Renders a course's sections and lessons with author controls (add / rename /
  delete / reorder / toggle-preview). Emits parent-supplied event names; takes
  plain assigns only — no resource, domain, or route-helper references, per the
  StalwartUI extraction discipline (see COMPONENTS.md).
  """
  use Phoenix.Component

  attr :sections, :list,
    required: true,
    doc:
      "sorted list of %{id, title, lessons: [%{id, title, free_preview}]} — lessons pre-sorted"

  attr :on_add_section, :string, default: "add_section"
  attr :on_rename_section, :string, default: "rename_section"
  attr :on_delete_section, :string, default: "delete_section"
  attr :on_move_section, :string, default: "move_section"
  attr :on_add_lesson, :string, default: "add_lesson"
  attr :on_rename_lesson, :string, default: "rename_lesson"
  attr :on_delete_lesson, :string, default: "delete_lesson"
  attr :on_move_lesson, :string, default: "move_lesson"
  attr :on_toggle_preview, :string, default: "toggle_preview"

  def curriculum_tree(assigns) do
    ~H"""
    <div id="curriculum-tree" class="space-y-4">
      <section :for={section <- @sections} id={"section-#{section.id}"} class="rounded border p-3">
        <div class="flex items-center gap-2">
          <form phx-submit={@on_rename_section} class="flex items-center gap-1">
            <input type="hidden" name="id" value={section.id} />
            <input type="text" name="title" value={section.title} class="input input-sm input-bordered" />
            <button type="submit" class="btn btn-sm">Save</button>
          </form>
          <button
            type="button"
            phx-click={@on_move_section}
            phx-value-id={section.id}
            phx-value-direction="up"
            class="btn btn-xs"
          >↑</button>
          <button
            type="button"
            phx-click={@on_move_section}
            phx-value-id={section.id}
            phx-value-direction="down"
            class="btn btn-xs"
          >↓</button>
          <button
            type="button"
            phx-click={@on_delete_section}
            phx-value-id={section.id}
            data-confirm="Delete this section and its lessons?"
            class="btn btn-xs btn-error"
          >Delete</button>
        </div>

        <ul class="mt-2 space-y-1">
          <li :for={lesson <- section.lessons} id={"lesson-#{lesson.id}"} class="flex items-center gap-2">
            <form phx-submit={@on_rename_lesson} class="flex items-center gap-1">
              <input type="hidden" name="id" value={lesson.id} />
              <input type="text" name="title" value={lesson.title} class="input input-xs input-bordered" />
              <button type="submit" class="btn btn-xs">Save</button>
            </form>
            <span :if={lesson.free_preview} class="badge badge-success badge-sm">Preview</span>
            <button
              type="button"
              phx-click={@on_toggle_preview}
              phx-value-id={lesson.id}
              class="btn btn-xs"
            >Toggle preview</button>
            <button type="button" phx-click={@on_move_lesson} phx-value-id={lesson.id} phx-value-direction="up" class="btn btn-xs">↑</button>
            <button type="button" phx-click={@on_move_lesson} phx-value-id={lesson.id} phx-value-direction="down" class="btn btn-xs">↓</button>
            <button
              type="button"
              phx-click={@on_delete_lesson}
              phx-value-id={lesson.id}
              data-confirm="Delete this lesson?"
              class="btn btn-xs btn-error"
            >Delete</button>
          </li>
        </ul>

        <form phx-submit={@on_add_lesson} class="mt-2 flex items-center gap-1">
          <input type="hidden" name="id" value={section.id} />
          <input type="text" name="title" placeholder="New lesson title" class="input input-xs input-bordered" />
          <button type="submit" class="btn btn-xs btn-primary">Add lesson</button>
        </form>
      </section>

      <p :if={@sections == []} class="text-sm opacity-70">No sections yet.</p>

      <form phx-submit={@on_add_section} class="flex items-center gap-1">
        <input type="text" name="title" placeholder="New section title" class="input input-sm input-bordered" />
        <button type="submit" class="btn btn-sm btn-primary">Add section</button>
      </form>
    </div>
    """
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/stalwart_ui/curriculum_tree_test.exs`
Expected: PASS.

- [ ] **Step 5: Document the component**

Append to `COMPONENTS.md`:

```markdown
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
```

- [ ] **Step 6: Format, lint, commit**

```bash
mix format
mix credo --strict
git add lib/stalwart_ui/curriculum_tree.ex test/stalwart_ui/curriculum_tree_test.exs COMPONENTS.md
git commit -m "Add StalwartUI.CurriculumTree component"
```

---

## Task 5: Course index LiveView (`/g/:slug/courses`)

Lists the gym's courses for a curriculum manager and creates new ones. Non-managers see an access notice. Follows `GymShowLive` exactly for `on_mount`, membership gating, and layout.

**Files:**
- Create: `lib/matwork_web/live/course_index_live.ex`
- Modify: `lib/matwork_web/router.ex`
- Test: `test/matwork_web/live/course_index_live_test.exs`

**Interfaces:**
- Consumes: `Curriculum.list_courses!/1`, `Curriculum.add_course/3` (Task 1); `MatworkWeb.GymLiveAuth` assigns `current_gym`, `current_user`, `current_membership`.
- Produces: route `live "/courses", CourseIndexLive` in the `:gym_routes` session; links to `~p"/g/#{slug}/courses/#{id}/edit"` (the Task 6 builder).

- [ ] **Step 1: Add the route**

In `lib/matwork_web/router.ex`, inside `ash_authentication_live_session :gym_routes do ... end` (currently holding `live "/"` and `live "/invite/:token"`), add:

```elixir
      live "/courses", CourseIndexLive
      live "/courses/:id/edit", CourseBuilderLive
```

(Both routes are added now; `CourseBuilderLive` is built in Task 6. If you run the server between tasks, comment the builder line until Task 6.)

- [ ] **Step 2: Write the failing test**

Create `test/matwork_web/live/course_index_live_test.exs` (mirrors `test/matwork_web/live/gym_show_live_test.exs`):

```elixir
defmodule MatworkWeb.CourseIndexLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  test "an owner sees the course list and can create a course", %{conn: conn} do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    generate(course(gym: gym, title: "Existing Course"))

    conn = sign_in(conn, owner)
    {:ok, lv, html} = live(conn, ~p"/g/#{gym.slug}/courses")

    assert html =~ "Existing Course"

    lv
    |> form("#new-course-form", form: %{title: "Half Guard"})
    |> render_submit()

    assert render(lv) =~ "Half Guard"
  end

  test "a student cannot see the course builder list", %{conn: conn} do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    student = generate(user())
    generate(membership(gym: gym, user: student, role: :student))

    conn = sign_in(conn, student)
    {:ok, _lv, html} = live(conn, ~p"/g/#{gym.slug}/courses")

    assert html =~ "don't have access"
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `mix test test/matwork_web/live/course_index_live_test.exs`
Expected: FAIL — `CourseIndexLive` undefined / route not found.

- [ ] **Step 4: Write the LiveView**

Create `lib/matwork_web/live/course_index_live.ex`:

```elixir
defmodule MatworkWeb.CourseIndexLive do
  use MatworkWeb, :live_view

  alias Matwork.Curriculum

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(_params, _session, socket) do
    {:ok, assign_courses(socket)}
  end

  def handle_event("create_course", %{"form" => %{"title" => title}}, socket) do
    gym = socket.assigns.current_gym

    case Curriculum.add_course(gym.id, title,
           actor: socket.assigns.current_user,
           tenant: gym.id
         ) do
      {:ok, _course} ->
        {:noreply, socket |> put_flash(:info, "Course created") |> assign_courses()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create course")}
    end
  end

  defp assign_courses(socket) do
    gym = socket.assigns.current_gym
    membership = socket.assigns.current_membership

    if manager?(membership) do
      courses =
        Curriculum.list_courses!(actor: socket.assigns.current_user, tenant: gym.id)
        |> Enum.sort_by(& &1.position)

      assign(socket, courses: courses, manager?: true)
    else
      assign(socket, courses: [], manager?: false)
    end
  end

  defp manager?(nil), do: false
  defp manager?(membership), do: membership.role in [:owner, :instructor]

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
      <.header>Courses</.header>

      <div :if={!@manager?}>
        <p>You don't have access to manage this gym's curriculum.</p>
      </div>

      <div :if={@manager?}>
        <ul id="course-list" class="space-y-2">
          <li :for={course <- @courses} id={"course-#{course.id}"}>
            <.link navigate={~p"/g/#{@current_gym.slug}/courses/#{course.id}/edit"}>
              {course.title}
            </.link>
            <span class="badge badge-sm">{course.status}</span>
          </li>
        </ul>
        <p :if={@courses == []} class="text-sm opacity-70">No courses yet.</p>

        <form id="new-course-form" phx-submit="create_course" class="mt-4 flex items-center gap-2">
          <input type="text" name="form[title]" placeholder="New course title" class="input input-bordered" />
          <button type="submit" class="btn btn-primary">Create course</button>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/matwork_web/live/course_index_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Format, lint, commit**

```bash
mix format
mix credo --strict
git add lib/matwork_web/router.ex lib/matwork_web/live/course_index_live.ex test/matwork_web/live/course_index_live_test.exs
git commit -m "Add course index LiveView"
```

---

## Task 6: Course builder LiveView (`/g/:slug/courses/:id/edit`)

The single-page builder. Loads one course with its sections (each with lessons), both sorted by `position`, and wires the `CurriculumTree` component's events to the domain functions. Also exposes publish/archive/unarchive.

**Files:**
- Create: `lib/matwork_web/live/course_builder_live.ex`
- Modify: `lib/matwork_web/router.ex` (route added in Task 5 — uncomment if you commented it)
- Test: `test/matwork_web/live/course_builder_live_test.exs`

**Interfaces:**
- Consumes: `StalwartUI.CurriculumTree.curriculum_tree/1` (Task 4); domain functions `get_course/2`, `add_section/3`, `update_section/3`, `destroy_section/2`, `reorder_section/3`, `add_lesson/3`, `update_lesson/3`, `destroy_lesson/2`, `reorder_lesson/3`, `set_lesson_preview/3`, `publish_course/2`, `archive_course/2`, `unarchive_course/2` (Tasks 1–3).
- Produces: the `/courses/:id/edit` behavior.

- [ ] **Step 1: Write the failing test**

Create `test/matwork_web/live/course_builder_live_test.exs`:

```elixir
defmodule MatworkWeb.CourseBuilderLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  alias Matwork.Curriculum

  setup do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    course = generate(course(gym: gym, title: "Half Guard"))
    %{owner: owner, gym: gym, course: course}
  end

  test "owner builds a section then a lesson", %{conn: conn, owner: owner, gym: gym, course: course} do
    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    lv |> form("#curriculum-tree form[phx-submit=add_section]", %{title: "Sweeps"}) |> render_submit()
    assert render(lv) =~ "Sweeps"

    lv
    |> form("#curriculum-tree form[phx-submit=add_lesson]", %{title: "Old-school sweep"})
    |> render_submit()

    assert render(lv) =~ "Old-school sweep"
  end

  test "owner can publish the course", %{conn: conn, owner: owner, gym: gym, course: course} do
    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    lv |> element("button", "Publish") |> render_click()

    reloaded = Curriculum.get_course!(course.id, actor: owner, tenant: gym.id)
    assert reloaded.status == :published
  end

  test "a student is denied the builder", %{conn: conn, gym: gym, course: course} do
    student = generate(user())
    generate(membership(gym: gym, user: student, role: :student))

    conn = sign_in(conn, student)
    {:ok, _lv, html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    assert html =~ "don't have access"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/matwork_web/live/course_builder_live_test.exs`
Expected: FAIL — `CourseBuilderLive` undefined.

- [ ] **Step 3: Write the LiveView**

Create `lib/matwork_web/live/course_builder_live.ex`. It loads the course + nested sorted sections/lessons, maps them to the plain shape `CurriculumTree` expects, and handles each event. Every write reloads the tree so the UI reflects the new order/state.

```elixir
defmodule MatworkWeb.CourseBuilderLive do
  use MatworkWeb, :live_view

  import StalwartUI.CurriculumTree

  alias Matwork.Curriculum

  require Ash.Query

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(%{"id" => course_id}, _session, socket) do
    membership = socket.assigns.current_membership

    if manager?(membership) do
      {:ok, socket |> assign(:course_id, course_id) |> load_course()}
    else
      {:ok, assign(socket, manager?: false, course: nil, sections: [])}
    end
  end

  # --- section events ---

  def handle_event("add_section", %{"title" => title}, socket) do
    Curriculum.add_section(socket.assigns.course, title, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("rename_section", %{"id" => id, "title" => title}, socket) do
    section = find_section(socket, id)
    Curriculum.update_section(section, %{title: title}, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("delete_section", %{"id" => id}, socket) do
    section = find_section(socket, id)
    Curriculum.destroy_section(section, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("move_section", %{"id" => id, "direction" => direction}, socket) do
    section = find_section(socket, id)
    Curriculum.reorder_section(section, to_direction(direction), opts(socket))
    {:noreply, load_course(socket)}
  end

  # --- lesson events ---

  def handle_event("add_lesson", %{"id" => section_id, "title" => title}, socket) do
    section = find_section(socket, section_id)
    Curriculum.add_lesson(section, title, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("rename_lesson", %{"id" => id, "title" => title}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.update_lesson(lesson, %{title: title}, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("delete_lesson", %{"id" => id}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.destroy_lesson(lesson, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("move_lesson", %{"id" => id, "direction" => direction}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.reorder_lesson(lesson, to_direction(direction), opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("toggle_preview", %{"id" => id}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.set_lesson_preview(lesson, !lesson.free_preview, opts(socket))
    {:noreply, load_course(socket)}
  end

  # --- course status events ---

  def handle_event("publish", _params, socket) do
    Curriculum.publish_course(socket.assigns.course, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("archive", _params, socket) do
    Curriculum.archive_course(socket.assigns.course, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("unarchive", _params, socket) do
    Curriculum.unarchive_course(socket.assigns.course, opts(socket))
    {:noreply, load_course(socket)}
  end

  # --- helpers ---

  defp opts(socket) do
    gym = socket.assigns.current_gym
    [actor: socket.assigns.current_user, tenant: gym.id]
  end

  defp manager?(nil), do: false
  defp manager?(membership), do: membership.role in [:owner, :instructor]

  defp to_direction("up"), do: :up
  defp to_direction("down"), do: :down

  defp find_section(socket, id), do: Enum.find(socket.assigns.raw_sections, &(&1.id == id))

  defp find_lesson(socket, id) do
    socket.assigns.raw_sections
    |> Enum.flat_map(& &1.lessons)
    |> Enum.find(&(&1.id == id))
  end

  # Loads the course with sections (sorted) each loading lessons (sorted).
  # Keeps the raw Ash structs (for event handlers) and a plain-map projection
  # (for the CurriculumTree component).
  defp load_course(socket) do
    lessons_query = Ash.Query.sort(Matwork.Curriculum.Lesson, position: :asc)

    sections_query =
      Matwork.Curriculum.CourseSection
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.load(lessons: lessons_query)

    course =
      Curriculum.get_course!(
        socket.assigns.course_id,
        Keyword.put(opts(socket), :load, sections: sections_query)
      )

    raw_sections = course.sections

    tree_sections =
      Enum.map(raw_sections, fn section ->
        %{
          id: section.id,
          title: section.title,
          lessons:
            Enum.map(section.lessons, fn lesson ->
              %{id: lesson.id, title: lesson.title, free_preview: lesson.free_preview}
            end)
        }
      end)

    assign(socket, course: course, raw_sections: raw_sections, sections: tree_sections, manager?: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
      <div :if={!@manager?}>
        <p>You don't have access to manage this gym's curriculum.</p>
      </div>

      <div :if={@manager?}>
        <.header>
          {@course.title}
          <span class="badge">{@course.status}</span>
          <:actions>
            <button phx-click="publish" class="btn btn-sm btn-primary">Publish</button>
            <button phx-click="archive" class="btn btn-sm">Archive</button>
            <button phx-click="unarchive" class="btn btn-sm">Unarchive</button>
          </:actions>
        </.header>

        <.curriculum_tree sections={@sections} />
      </div>
    </Layouts.app>
    """
  end
end
```

Note on the `Lesson` load: the nested `load: [sections: sections_query]` where `sections_query` itself `load`s `lessons` is the Ash idiom for a two-level sorted load. If the `Lesson` relationship name on `CourseSection` differs, add `has_many :lessons, Matwork.Curriculum.Lesson` to `CourseSection` (Task 2) — **do this now if the load errors**: Ash's `belongs_to :section` on `Lesson` does not auto-create the inverse `has_many`. Add to `CourseSection`'s `relationships do` block:

```elixir
    has_many :lessons, Matwork.Curriculum.Lesson do
      destination_attribute :section_id
    end
```

Add the same-shaped `has_many :sections` to `Course` (Task 1's resource) for the section load:

```elixir
    has_many :sections, Matwork.Curriculum.CourseSection do
      destination_attribute :course_id
    end
```

⚠️ **If you already reached Task 6 without these `has_many` relationships, add them to the Task 1 / Task 2 resources now** (they're required for the nested load), regenerate nothing (relationships are not schema changes), and re-run those tasks' tests to confirm they still pass.

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/matwork_web/live/course_builder_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Full suite + lint**

Run: `mix test` (expect all green, including the 74 pre-existing M0 tests) and `mix credo --strict`.

- [ ] **Step 6: Format, commit**

```bash
mix format
git add lib/matwork_web/live/course_builder_live.ex lib/matwork/curriculum/course.ex lib/matwork/curriculum/course_section.ex test/matwork_web/live/course_builder_live_test.exs
git commit -m "Add course builder LiveView"
```

- [ ] **Step 7: Manual smoke test (optional but recommended)**

Run `mix phx.server`, create a gym (or use a seeded one), visit `/g/<slug>/courses`, create a course, open its builder, add a section and a lesson, reorder them, toggle a preview, publish. Confirm each action persists across a refresh.

---

## Self-Review (completed while writing)

**Spec coverage** (against `docs/superpowers/specs/2026-07-16-milestone-1-curriculum-video-design.md` §2.1, §3.1–3.2, §4):

- §2.1 `Course`/`CourseSection`/`Lesson` with the listed attributes → Tasks 1–3. `video_id`/`request_playback_token` correctly deferred to Session 2/3 (noted in Lesson moduledoc).
- §3.1 `ManagesCurriculum` gating create/update/publish/archive/reorder/destroy → Task 1 Step 2, applied in every resource's policy block. Deny paths (student, non-member) tested in all three resource tests.
- §3.2 read gating: instructors see all, students see published only, sections/lessons inherit via course → `CourseVisible`/`SectionVisible`/`LessonVisible` (Tasks 1–3), each with a student-visibility test + tenant-isolation test.
- §4.1 routes `/courses`, `/courses/new` (folded into the index create form), `/courses/:id/edit` → Tasks 5–6.
- §4.2 single-page builder with inline add/rename/delete/reorder/toggle + publish/archive → Task 6.
- §4.3 `CurriculumTree` StalwartUI component, plain assigns → Task 4, `COMPONENTS.md` updated.
- §4.4 tests: allow+deny per action, tenant isolation, read filter, reorder, builder LiveView flow → covered across Tasks 1–3, 5–6.

**Placeholder scan:** none — every step has concrete code/commands. The only conditional is the `has_many` note in Task 6, which gives the exact code to add.

**Type/name consistency:** `add_course/add_section/add_lesson`, `reorder_section/reorder_lesson`, `set_lesson_preview`, `swap_position/6`, `next_position/3`, and the `set_*_position!` interfaces are used identically where defined and consumed. Generator names `course/section/lesson` match their call sites. Event-name strings in `CurriculumTree` defaults (`add_section`, `move_section`, …) match the builder's `handle_event` clauses exactly.

**Open risk flagged for the implementer:** the two-level nested sorted load in Task 6 depends on `has_many :sections`/`:lessons` inverse relationships — the plan adds them explicitly with a ⚠️ callout. Confirm via `mix usage_rules.docs Ash.Query.load` if the load shape errors.
