defmodule MatworkWeb.GymNewLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  describe "mount" do
    test "requires a signed-in user", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/gyms/new")
    end
  end

  describe "nav bar" do
    test "shows the Matwork brand mark and signed-in actions", %{conn: conn} do
      owner = generate(user())
      conn = sign_in(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/gyms/new")

      assert has_element?(view, "#nav-brand", "Matwork")
      assert has_element?(view, "#nav-user-email", to_string(Ash.CiString.value(owner.email)))
      assert has_element?(view, "#nav-create-gym")
      assert has_element?(view, "#nav-sign-out")
    end
  end

  describe "save" do
    test "creates a gym and navigates to its page", %{conn: conn} do
      owner = generate(user())
      conn = sign_in(conn, owner)

      {:ok, view, _html} = live(conn, ~p"/gyms/new")

      assert {:error, {:live_redirect, %{to: "/g/rickson-academy"}}} =
               view
               |> form("#gym-form", form: %{name: "Rickson's Academy", slug: "rickson-academy"})
               |> render_submit()

      assert {:ok, gym} = Matwork.Gyms.get_gym_by_slug("rickson-academy", actor: owner)
      assert gym.owner_id == owner.id
    end

    test "shows validation errors for a taken slug", %{conn: conn} do
      owner = generate(user())
      Matwork.Gyms.create_gym!("Existing Gym", "taken-slug", actor: owner)

      other_user = generate(user())
      conn = sign_in(conn, other_user)

      {:ok, view, _html} = live(conn, ~p"/gyms/new")

      html =
        view
        |> form("#gym-form", form: %{name: "New Gym", slug: "taken-slug"})
        |> render_submit()

      assert html =~ "has already been taken" or html =~ "taken"
    end
  end
end
