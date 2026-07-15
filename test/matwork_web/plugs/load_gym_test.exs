defmodule MatworkWeb.Plugs.LoadGymTest do
  use MatworkWeb.ConnCase, async: true

  import Matwork.Generator

  alias MatworkWeb.Plugs.LoadGym

  describe "call/2" do
    test "assigns current_gym and current_membership for the gym's owner", %{conn: conn} do
      owner = generate(user())
      gym = Matwork.Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      conn =
        conn
        |> sign_in(owner)
        |> Map.put(:params, %{"slug" => "rickson-academy"})
        |> LoadGym.call([])

      assert conn.assigns.current_gym.id == gym.id
      assert conn.assigns.current_membership.role == :owner
      assert Ash.PlugHelpers.get_tenant(conn) == gym.id
    end

    test "assigns current_membership nil for a signed-in stranger", %{conn: conn} do
      owner = generate(user())
      Matwork.Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)
      stranger = generate(user())

      conn =
        conn
        |> sign_in(stranger)
        |> Map.put(:params, %{"slug" => "rickson-academy"})
        |> LoadGym.call([])

      refute conn.halted
      assert conn.assigns.current_gym.slug == Ash.CiString.new("rickson-academy")
      assert conn.assigns.current_membership == nil
    end

    test "assigns current_gym for an unauthenticated visitor (public read)", %{conn: conn} do
      owner = generate(user())
      Matwork.Gyms.create_gym!("Rickson's Academy", "rickson-academy", actor: owner)

      conn =
        conn
        |> Map.put(:params, %{"slug" => "rickson-academy"})
        |> LoadGym.call([])

      refute conn.halted
      assert conn.assigns.current_gym.slug == Ash.CiString.new("rickson-academy")
      assert conn.assigns.current_membership == nil
    end

    test "404s for a nonexistent slug", %{conn: conn} do
      conn =
        conn
        |> Map.put(:params, %{"slug" => "does-not-exist"})
        |> LoadGym.call([])

      assert conn.halted
      assert conn.status == 404
    end
  end
end
