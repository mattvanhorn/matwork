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
