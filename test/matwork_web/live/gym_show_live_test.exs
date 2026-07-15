defmodule MatworkWeb.GymShowLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  alias Matwork.Gyms

  describe "as the gym's owner" do
    test "shows the roster and an invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      conn = sign_in(conn, owner)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert html =~ to_string(Ash.CiString.value(student.email))
      assert has_element?(view, "#invite-form")
    end

    test "sending an invite adds it and re-renders the invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))

      conn = sign_in(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}")

      html =
        view
        |> form("#invite-form", form: %{email: "student@example.com", role: "student"})
        |> render_submit()

      assert html =~ "Invite sent"
      assert length(Gyms.list_invites!(actor: owner, tenant: gym.id)) == 1
    end
  end

  describe "as a student" do
    test "shows the roster but no invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      conn = sign_in(conn, student)
      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}")

      refute has_element?(view, "#invite-form")
    end
  end

  describe "as someone with no membership" do
    test "shows the access message instead of the roster", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      stranger = generate(user())

      conn = sign_in(conn, stranger)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert html =~ "have access to this gym"
      refute has_element?(view, "#roster")
    end
  end

  test "404s for a nonexistent gym", %{conn: conn} do
    owner = generate(user())
    conn = sign_in(conn, owner)

    assert conn |> get(~p"/g/does-not-exist") |> Phoenix.ConnTest.response(404)
  end
end
