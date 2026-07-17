defmodule Matwork.Curriculum.CourseTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Curriculum

  describe "create / update (write gating)" do
    test "an owner can create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      {:ok, course} = Curriculum.add_course("Half Guard", actor: owner, tenant: gym.id)

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
        Curriculum.add_course("Guard Passing", actor: instructor, tenant: gym.id)

      assert course.title == "Guard Passing"
    end

    test "a student cannot create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.add_course("Nope", actor: student, tenant: gym.id)
    end

    test "a non-member cannot create a course" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      stranger = generate(user())

      assert {:error, %Ash.Error.Forbidden{}} =
               Curriculum.add_course("Nope", actor: stranger, tenant: gym.id)
    end

    test "add_course appends at the next position" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      {:ok, first} = Curriculum.add_course("One", actor: owner, tenant: gym.id)
      {:ok, second} = Curriculum.add_course("Two", actor: owner, tenant: gym.id)

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
      _gym_a = generate(gym(owner: owner_a))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      generate(course(gym: gym_b, status: :published))

      assert Curriculum.list_courses!(actor: owner_a, tenant: gym_b.id) == []
    end
  end
end
