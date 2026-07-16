defmodule Matwork.Accounts.UserTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Accounts.User

  describe "read policy (roster visibility)" do
    test "a user can always read their own record regardless of gym membership" do
      user = generate(user())

      assert %User{id: id} = Ash.get!(User, user.id, actor: user)
      assert id == user.id
    end

    test "an instructor at gym A can read a fellow gym A member's record" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))
      instructor_a = generate(user())
      generate(membership(gym: gym_a, user: instructor_a, role: :instructor))
      student_a = generate(user())
      generate(membership(gym: gym_a, user: student_a, role: :student))

      assert %User{id: id} =
               Ash.get!(User, student_a.id, actor: instructor_a, tenant: gym_a.id)

      assert id == student_a.id
    end

    test "an instructor at gym A cannot read the record of a user who is only a member of gym B" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))
      instructor_a = generate(user())
      generate(membership(gym: gym_a, user: instructor_a, role: :instructor))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      gym_b_only_user = generate(user())
      generate(membership(gym: gym_b, user: gym_b_only_user, role: :student))

      assert {:error, _} =
               Ash.get(User, gym_b_only_user.id, actor: instructor_a, tenant: gym_a.id)
    end

    test "an owner at gym A cannot read the record of a user who is only a member of gym B" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      gym_b_only_user = generate(user())
      generate(membership(gym: gym_b, user: gym_b_only_user, role: :student))

      assert {:error, _} =
               Ash.get(User, gym_b_only_user.id, actor: owner_a, tenant: gym_a.id)
    end

    test "a student cannot read another member's record even within the same gym" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      other_student = generate(user())
      generate(membership(gym: gym, user: other_student, role: :student))

      assert {:error, _} = Ash.get(User, other_student.id, actor: student, tenant: gym.id)
    end

    test "an unauthenticated (nil) actor cannot read another user's record and does not crash" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      assert {:error, _} = Ash.get(User, owner.id, actor: nil, tenant: gym.id)
    end
  end
end
