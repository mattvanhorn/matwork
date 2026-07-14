defmodule Matwork.Gyms.GymTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Gyms

  describe "create" do
    test "an authenticated user can create a gym and becomes its owner" do
      owner = generate(user())

      gym =
        Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      assert gym.name == "Rickson's Academy"
      assert gym.owner_id == owner.id
    end

    test "no actor cannot create a gym" do
      assert_raise Ash.Error.Invalid, fn ->
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

    test "creating a gym also creates the owner's active owner Membership" do
      owner = generate(user())

      gym = Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      roster = Gyms.list_memberships!(actor: owner, tenant: gym.id)

      assert [%{role: :owner, status: :active, user_id: owner_id}] = roster
      assert owner_id == owner.id
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
