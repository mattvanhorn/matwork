defmodule MatworkWeb.CourseBuilderLiveTest do
  use MatworkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Matwork.Generator

  alias Matwork.Curriculum

  setup do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    course = generate(course(gym: gym, title: "Half Guard"))
    %{owner: owner, gym: gym, course: course}
  end

  test "owner builds a section then a lesson", %{
    conn: conn,
    owner: owner,
    gym: gym,
    course: course
  } do
    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    lv
    |> form("#curriculum-tree form[phx-submit=add_section]", %{title: "Sweeps"})
    |> render_submit()

    assert render(lv) =~ "Sweeps"

    lv
    |> form("#curriculum-tree form[phx-submit=add_lesson]", %{title: "Old-school sweep"})
    |> render_submit()

    assert render(lv) =~ "Old-school sweep"
  end

  test "owner can publish the course", %{conn: conn, owner: owner, gym: gym, course: course} do
    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    lv |> element("button", "Publish") |> render_click()

    reloaded = Curriculum.get_course!(course.id, actor: owner, tenant: gym.id)
    assert reloaded.status == :published
  end

  test "a student is denied the builder", %{conn: conn, gym: gym, course: course} do
    student = generate(user())
    generate(membership(gym: gym, user: student, role: :student))

    conn = sign_in(conn, student)
    {:ok, _lv, html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    assert html =~ "have access"
  end

  test "owner deletes a section via the Delete button's JS.push command", %{
    conn: conn,
    owner: owner,
    gym: gym,
    course: course
  } do
    section = generate(section(course: course, title: "Sweeps"))

    conn = sign_in(conn, owner)
    {:ok, lv, html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")
    assert html =~ "Sweeps"

    lv
    |> element("#section-#{section.id} button", "Delete")
    |> render_click()

    refute render(lv) =~ "Sweeps"
  end

  test "a stale section id flashes instead of crashing", %{
    conn: conn,
    owner: owner,
    gym: gym,
    course: course
  } do
    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    html =
      render_submit(lv, "rename_section", %{"_id" => Ash.UUID.generate(), "title" => "Ghost"})

    assert html =~ "no longer exists"
    refute html =~ "Ghost"
  end

  test "an unexpected direction value flashes/no-ops instead of crashing", %{
    conn: conn,
    owner: owner,
    gym: gym,
    course: course
  } do
    section = generate(section(course: course))

    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    html =
      render_click(lv, "move_section", %{"id" => section.id, "direction" => "sideways"})

    assert html =~ section.title
  end

  test "a missing course id redirects to the course index instead of crashing", %{
    conn: conn,
    owner: owner,
    gym: gym
  } do
    conn = sign_in(conn, owner)

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/g/#{gym.slug}/courses/#{Ash.UUID.generate()}/edit")

    assert to == ~p"/g/#{gym.slug}/courses"
    assert flash["error"] == "Course not found."
  end
end
