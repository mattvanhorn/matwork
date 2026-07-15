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

    test "an owner can invite an instructor" do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      invite =
        Gyms.create_invite!("future-instructor@example.com", :instructor,
          actor: owner,
          tenant: gym.id
        )

      assert invite.role == :instructor
    end

    test "an instructor cannot invite an owner" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.create_invite!("new-owner@example.com", :owner, actor: instructor, tenant: gym.id)
      end
    end

    test "an instructor cannot invite another instructor" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.create_invite!("new-instructor@example.com", :instructor,
          actor: instructor,
          tenant: gym.id
        )
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

  describe "mark_accepted" do
    test "accepting an invite sets accepted_at, even for an actor with no membership" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invited_student = generate(user())

      invite =
        Gyms.create_invite!(Ash.CiString.value(invited_student.email), :student,
          actor: owner,
          tenant: gym.id
        )

      accepted =
        Gyms.mark_invite_accepted!(invite, actor: invited_student, tenant: gym.id)

      refute is_nil(accepted.accepted_at)
    end

    test "an unrelated actor cannot mark someone else's invite accepted" do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      unrelated_user = generate(user())

      assert_raise Ash.Error.Forbidden, fn ->
        Gyms.mark_invite_accepted!(invite, actor: unrelated_user, tenant: gym.id)
      end
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

    test "tenancy isolation: an owner of gym A cannot see gym B's invites" do
      owner_a = generate(user())
      gym_a = generate(gym(owner: owner_a))
      generate(invite(gym: gym_a, inviter: owner_a))

      owner_b = generate(user())
      gym_b = generate(gym(owner: owner_b))
      generate(invite(gym: gym_b, inviter: owner_b))

      invites = Gyms.list_invites!(actor: owner_a, tenant: gym_b.id)

      assert invites == []
    end
  end
end
