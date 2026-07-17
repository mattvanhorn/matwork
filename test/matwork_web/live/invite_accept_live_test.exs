defmodule MatworkWeb.InviteAcceptLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  alias Matwork.Gyms

  describe "signed out" do
    test "shows a sign-in prompt", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-needs-sign-in")
      assert has_element?(view, "#nav-brand", gym.name)
      assert has_element?(view, "#nav-sign-in")
    end
  end

  describe "signed in with a matching email" do
    test "accepts the invite and redirects to the gym home page", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      student = generate(user(email: "student@example.com"))
      conn = sign_in(conn, student)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert to == ~p"/g/#{gym.slug}"

      membership = Gyms.get_membership_for_user!(student.id, actor: student, tenant: gym.id)
      assert membership.role == :student
      assert membership.status == :active
    end
  end

  describe "signed in with a non-matching email" do
    test "shows the invalid-invite message", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      other_user = generate(user())
      conn = sign_in(conn, other_user)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-invalid")
    end
  end

  describe "an already-accepted invite" do
    test "shows the invalid-invite message on the second attempt", %{conn: conn} do
      owner = generate(user())
      gym = generate(gym(owner: owner))
      invite = Gyms.create_invite!("student@example.com", :student, actor: owner, tenant: gym.id)

      student = generate(user(email: "student@example.com"))
      Gyms.accept_invite!(invite.token, actor: student, tenant: gym.id)

      conn = sign_in(conn, student)

      {:ok, view, _html} = live(conn, ~p"/g/#{gym.slug}/invite/#{invite.token}")

      assert has_element?(view, "#invite-invalid")
    end
  end
end
