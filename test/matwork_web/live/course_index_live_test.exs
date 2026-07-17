defmodule MatworkWeb.CourseIndexLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  test "an owner sees the course list and can create a course", %{conn: conn} do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    generate(course(gym: gym, title: "Existing Course"))

    conn = sign_in(conn, owner)
    {:ok, lv, html} = live(conn, ~p"/g/#{gym.slug}/courses")

    assert html =~ "Existing Course"

    lv
    |> form("#new-course-form", form: %{title: "Half Guard"})
    |> render_submit()

    assert render(lv) =~ "Half Guard"
  end

  test "a student cannot see the course builder list", %{conn: conn} do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    student = generate(user())
    generate(membership(gym: gym, user: student, role: :student))

    conn = sign_in(conn, student)
    {:ok, _lv, html} = live(conn, ~p"/g/#{gym.slug}/courses")

    assert html =~ "have access to manage this gym"
  end
end
