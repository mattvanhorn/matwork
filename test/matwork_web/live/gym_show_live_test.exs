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

    test "excludes removed members from the roster", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      removed_student = generate(user())
      removed_membership = generate(membership(gym: gym, user: removed_student, role: :student))
      Gyms.remove_membership!(removed_membership, actor: owner, tenant: gym.id)

      conn = sign_in(conn, owner)
      {:ok, _view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert html =~ to_string(Ash.CiString.value(student.email))
      refute html =~ to_string(Ash.CiString.value(removed_student.email))
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
    test "does not show the roster, an invite form, or another member's email", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))
      other_student = generate(user())
      generate(membership(gym: gym, user: other_student, role: :student))

      conn = sign_in(conn, student)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      refute has_element?(view, "#roster")
      refute has_element?(view, "#invite-form")
      assert has_element?(view, "#student-view")
      refute html =~ to_string(Ash.CiString.value(other_student.email))
      assert html =~ gym.name
    end
  end

  describe "as an instructor" do
    test "shows the roster and an invite form", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      instructor = generate(user())
      generate(membership(gym: gym, user: instructor, role: :instructor))
      student = generate(user())
      generate(membership(gym: gym, user: student, role: :student))

      conn = sign_in(conn, instructor)
      {:ok, view, html} = live(conn, ~p"/g/#{gym.slug}")

      assert html =~ to_string(Ash.CiString.value(student.email))
      assert has_element?(view, "#invite-form")
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
