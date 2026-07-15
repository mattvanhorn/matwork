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
