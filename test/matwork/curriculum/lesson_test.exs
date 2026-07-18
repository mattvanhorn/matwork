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

      {:ok, b} =
        Curriculum.add_lesson(section, "Far-side underhook", actor: owner, tenant: gym.id)

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

      # Denied either way: the resource's own create policy (ManagesCurriculum)
      # would reject a student outright, but since the parent course defaults
      # to :draft, SectionInTenant's actor-scoped exists check (see
      # Matwork.Curriculum.Checks.SectionVisible/CourseVisible — students only
      # see published courses) now denies visibility first, surfacing as
      # Invalid rather than Forbidden. Either error class correctly blocks
      # the write.
      assert {:error, _} = Curriculum.add_lesson(section, "Nope", actor: student, tenant: gym.id)
    end

    test "an instructor cannot attach a lesson to another gym's section" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))
      instructor_a = generate(user())
      generate(membership(gym: gym_a, user: instructor_a, role: :instructor))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      section_b = generate(section(course: generate(course(gym: gym_b))))

      assert {:error, %Ash.Error.Invalid{}} =
               Curriculum.add_lesson(section_b, "Cross-tenant",
                 actor: instructor_a,
                 tenant: gym_a.id
               )
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

    test "an unrecognized direction is a no-op, not a crash" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      section = generate(section(course: generate(course(gym: gym))))
      first = generate(lesson(section: section, position: 0))
      second = generate(lesson(section: section, position: 1))

      assert :ok = Curriculum.reorder_lesson(first, :sideways, actor: owner, tenant: gym.id)

      ordered =
        Curriculum.list_lessons!(actor: owner, tenant: gym.id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert ordered == [first.id, second.id]
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
