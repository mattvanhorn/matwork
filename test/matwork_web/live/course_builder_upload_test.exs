defmodule MatworkWeb.CourseBuilderUploadTest do
  use MatworkWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import Matwork.Generator

  alias Matwork.Curriculum

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    course = generate(course(gym: gym, title: "Half Guard"))
    section = generate(section(course: course))
    lesson = generate(lesson(section: section, title: "Old-school sweep"))
    %{owner: owner, gym: gym, course: course, lesson: lesson}
  end

  test "requesting an upload creates a Video, attaches it, and returns the URL",
       %{conn: conn, owner: owner, gym: gym, course: course, lesson: lesson} do
    stub(Matwork.Platform.MuxMock, :create_direct_upload, fn %{passthrough: passthrough} ->
      assert passthrough == gym.id
      {:ok, %{id: "upload_live", url: "https://storage.example/put"}}
    end)

    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    # Simulate the JS hook's pushEvent for the lesson's upload control.
    render_hook(element(lv, "#upload-#{lesson.id}"), "request_upload", %{
      "lesson_id" => lesson.id
    })

    {:ok, reloaded} =
      Curriculum.get_course(course.id, actor: owner, tenant: gym.id)

    lesson_row =
      Curriculum.list_lessons!(actor: owner, tenant: gym.id)
      |> Enum.find(&(&1.id == lesson.id))

    assert lesson_row.video_id
    assert reloaded.id == course.id
  end

  test "a webhook-driven video_updated broadcast refreshes the builder to Ready",
       %{conn: conn, owner: owner, gym: gym, course: course, lesson: lesson} do
    video = generate(video(gym: gym, status: :processing))
    {:ok, _} = Curriculum.attach_lesson_video(lesson, video, actor: owner, tenant: gym.id)

    conn = sign_in(conn, owner)
    {:ok, lv, _html} = live(conn, ~p"/g/#{gym.slug}/courses/#{course.id}/edit")

    # Mark ready as the system actor, then broadcast the same message the job sends.
    {:ok, _} =
      Matwork.Media.mark_video_ready(video, %{mux_playback_id: "pb"},
        actor: %Matwork.Platform.SystemActor{},
        tenant: gym.id
      )

    Phoenix.PubSub.broadcast(Matwork.PubSub, "gym:#{gym.id}:videos", {:video_updated, video.id})

    assert render(lv) =~ "Ready"
  end
end
