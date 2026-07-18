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

      # Denied either way: the resource's own create policy (ManagesCurriculum)
      # would reject a student outright, but since this course defaults to
      # :draft, CourseInTenant's actor-scoped exists check (see
      # Matwork.Curriculum.Checks.CourseVisible — students only see published
      # courses) now denies visibility first, surfacing as Invalid rather than
      # Forbidden. Either error class correctly blocks the write.
      assert {:error, _} = Curriculum.add_section(course, "Nope", actor: student, tenant: gym.id)
    end

    test "an instructor cannot attach a section to another gym's course" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))
      instructor_a = generate(user())
      generate(membership(gym: gym_a, user: instructor_a, role: :instructor))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      course_b = generate(course(gym: gym_b))

      assert {:error, %Ash.Error.Invalid{}} =
               Curriculum.add_section(course_b, "Cross-tenant",
                 actor: instructor_a,
                 tenant: gym_a.id
               )
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

    test "moving the last section down is a no-op" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course = generate(course(gym: gym))
      first = generate(section(course: course, position: 0))
      second = generate(section(course: course, position: 1))

      :ok = Curriculum.reorder_section(second, :down, actor: owner, tenant: gym.id)

      ordered =
        Curriculum.list_sections!(actor: owner, tenant: gym.id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert ordered == [first.id, second.id]
    end

    test "reordering a section in one course does not touch another course's sections" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course_a = generate(course(gym: gym))
      course_b = generate(course(gym: gym))

      a_first = generate(section(course: course_a, position: 0))
      _a_second = generate(section(course: course_a, position: 1))
      b_first = generate(section(course: course_b, position: 0))
      b_second = generate(section(course: course_b, position: 1))

      :ok = Curriculum.reorder_section(a_first, :down, actor: owner, tenant: gym.id)

      b_ordered =
        Curriculum.list_sections!(actor: owner, tenant: gym.id)
        |> Enum.filter(&(&1.course_id == course_b.id))
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert b_ordered == [b_first.id, b_second.id]
    end

    test "reordering with a stale caller-held struct still produces correct final positions" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      course = generate(course(gym: gym))
      first = generate(section(course: course, position: 0))
      second = generate(section(course: course, position: 1))
      third = generate(section(course: course, position: 2))

      # A caller might hold a struct fetched before some other change landed;
      # its `position` field must not be trusted by `swap_position`.
      stale_first = %{first | position: 99}

      :ok = Curriculum.reorder_section(stale_first, :down, actor: owner, tenant: gym.id)

      ordered =
        Curriculum.list_sections!(actor: owner, tenant: gym.id)
        |> Enum.sort_by(& &1.position)
        |> Enum.map(& &1.id)

      assert ordered == [second.id, first.id, third.id]
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

    test "tenancy isolation: an instructor in gym A cannot read gym B's sections" do
      owner_a = generate(user())
      _gym_a = generate(gym(owner: owner_a))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      course_b = generate(course(gym: gym_b, status: :published))
      generate(section(course: course_b))

      assert Curriculum.list_sections!(actor: owner_a, tenant: gym_b.id) == []
    end
  end
end
