defmodule Matwork.Gyms.MembershipTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Gyms

  describe "create_owner" do
    test "the gym's owner can create their own owner membership" do
      owner = generate(user())

      # Seed the gym directly via the data layer, bypassing `Gym`'s :create
      # action (and therefore its after_action hook that auto-creates the
      # owner Membership), so this test can exercise `create_owner`'s allow
      # path in isolation from a clean slate.
      gym =
        Ash.Seed.seed!(Matwork.Gyms.Gym, %{
          name: "Rickson's Academy",
          slug: "rickson-academy-seeded",
          owner_id: owner.id
        })

      membership =
        Gyms.create_owner_membership!(owner.id, actor: owner, tenant: gym.id)

      assert membership.role == :owner
      assert membership.status == :active
      assert membership.user_id == owner.id
    end

    test "creating a duplicate owner membership fails on the unique constraint" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      # The owner membership is now auto-created when the gym is created.
      # Verify that we can't create another one (unique constraint).
      assert_raise Ash.Error.Invalid, fn ->
        Gyms.create_owner_membership!(owner.id, actor: owner, tenant: gym.id)
      end
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

      # Roster includes owner (auto-created) and student
      assert length(roster) == 2
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
      # Owner membership is auto-created, no need to generate it

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

    test "an owner can remove an instructor's membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      # Owner membership is auto-created, no need to generate it
      membership = generate(membership(gym: gym, user: instructor, role: :instructor))

      updated = Gyms.remove_membership!(membership, actor: owner, tenant: gym.id)

      assert updated.status == :removed
    end

    test "an instructor can remove a student's membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))
      student = generate(user())
      membership = generate(membership(gym: gym, user: student, role: :student))

      updated = Gyms.remove_membership!(membership, actor: instructor, tenant: gym.id)

      assert updated.status == :removed
    end

    test "an instructor cannot remove the owner's membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      # Owner membership is auto-created, fetch it from the list
      [owner_membership] =
        Gyms.list_memberships!(actor: owner, tenant: gym.id)
        |> Enum.filter(&(&1.role == :owner))

      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.remove_membership!(owner_membership, actor: instructor, tenant: gym.id)
      end
    end

    test "an instructor cannot remove another instructor's membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))
      other_instructor = generate(user())
      membership = generate(membership(gym: gym, user: other_instructor, role: :instructor))

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.remove_membership!(membership, actor: instructor, tenant: gym.id)
      end
    end
  end

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
end
