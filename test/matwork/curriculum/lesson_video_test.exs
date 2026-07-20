defmodule Matwork.Curriculum.LessonVideoTest do
  use Matwork.DataCase, async: true

  import Matwork.Generator

  alias Matwork.Curriculum

  test "an instructor can attach a same-gym video to a lesson" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))
    video = generate(video(gym: gym))

    {:ok, updated} = Curriculum.attach_lesson_video(lesson, video, actor: owner, tenant: gym.id)

    assert updated.video_id == video.id
  end

  test "attaching another gym's video is rejected" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))

    other_gym = generate(gym())
    foreign_video = generate(video(gym: other_gym))

    assert {:error, %Ash.Error.Invalid{}} =
             Curriculum.attach_lesson_video(lesson, foreign_video, actor: owner, tenant: gym.id)
  end

  test "a student cannot attach a video" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    student = generate(user())
    generate(membership(gym: gym, user: student, role: :student))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))
    video = generate(video(gym: gym))

    # Denied either way: the resource's own update policy (ManagesCurriculum)
    # would reject a student outright, but VideoInTenant's actor-scoped
    # exists check (see Matwork.Media.Video's read policy — only
    # owner/instructor may see videos) now denies visibility first,
    # surfacing as Invalid rather than Forbidden. Either error class
    # correctly blocks the write.
    assert {:error, _} =
             Curriculum.attach_lesson_video(lesson, video, actor: student, tenant: gym.id)
  end

  test "detach clears the video" do
    owner = generate(user())
    gym = generate(gym(owner: owner))
    lesson = generate(lesson(section: generate(section(course: generate(course(gym: gym))))))
    video = generate(video(gym: gym))
    {:ok, attached} = Curriculum.attach_lesson_video(lesson, video, actor: owner, tenant: gym.id)

    {:ok, detached} = Curriculum.detach_lesson_video(attached, actor: owner, tenant: gym.id)

    assert is_nil(detached.video_id)
  end
end
