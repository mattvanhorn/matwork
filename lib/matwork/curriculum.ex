defmodule Matwork.Curriculum do
  @moduledoc "The Curriculum domain: courses, sections, and lessons."
  use Ash.Domain,
    otp_app: :matwork,
    extensions: [AshPhoenix]

  require Ash.Query

  resources do
    resource Matwork.Curriculum.Course do
      define :create_course, action: :create, args: [:title]
      define :get_course, action: :read, get_by: [:id]
      define :list_courses, action: :read
      define :update_course, action: :update
      define :set_course_position, action: :set_position
      define :publish_course, action: :publish
      define :archive_course, action: :archive
      define :unarchive_course, action: :unarchive
    end

    resource Matwork.Curriculum.CourseSection do
      define :create_section, action: :create, args: [:course_id, :title]
      define :list_sections, action: :read
      define :update_section, action: :update
      define :set_section_position, action: :set_position
      define :destroy_section, action: :destroy
    end

    resource Matwork.Curriculum.Lesson do
      define :create_lesson, action: :create, args: [:section_id, :title]
      define :list_lessons, action: :read
      define :update_lesson, action: :update
      define :set_lesson_position, action: :set_position
      define :destroy_lesson, action: :destroy
      define :attach_lesson_video_by_id, action: :attach_video
      define :detach_lesson_video, action: :detach_video
    end
  end

  @doc """
  Create a course at the end of the gym's course list (next `position`).
  `opts` must include `:actor` and `:tenant` — the target gym is
  `opts[:tenant]` (multitenancy requires every write to match it).
  """
  def add_course(title, opts) do
    position = next_position(Matwork.Curriculum.Course, [], opts)
    create_course(title, %{position: position}, opts)
  end

  @doc "Create a section at the end of its course. `opts` needs `:actor` and `:tenant`."
  def add_section(course, title, opts) do
    position = next_position(Matwork.Curriculum.CourseSection, [course_id: course.id], opts)
    create_section(course.id, title, %{position: position}, opts)
  end

  @doc "Move a section one slot `:up` or `:down` among its course siblings."
  def reorder_section(section, direction, opts) do
    swap_position(
      Matwork.Curriculum.CourseSection,
      [course_id: section.course_id],
      section,
      direction,
      &set_section_position!/3,
      opts
    )
  end

  @doc "Create a lesson at the end of its section."
  def add_lesson(section, title, opts) do
    position = next_position(Matwork.Curriculum.Lesson, [section_id: section.id], opts)
    create_lesson(section.id, title, %{position: position}, opts)
  end

  @doc "Toggle/set a lesson's free-preview flag."
  def set_lesson_preview(lesson, value, opts) when is_boolean(value) do
    update_lesson(lesson, %{free_preview: value}, opts)
  end

  @doc "Attach `video` to `lesson` (both must be in `opts[:tenant]`)."
  def attach_lesson_video(lesson, video, opts) do
    attach_lesson_video_by_id(lesson, %{video_id: video.id}, opts)
  end

  @doc "Move a lesson one slot `:up`/`:down` among its section siblings."
  def reorder_lesson(lesson, direction, opts) do
    swap_position(
      Matwork.Curriculum.Lesson,
      [section_id: lesson.section_id],
      lesson,
      direction,
      &set_lesson_position!/3,
      opts
    )
  end

  @doc """
  Loads a course with its sections and each section's lessons, both levels
  sorted by `position` — the shape the course builder LiveView renders.
  `opts` must include `:actor` and `:tenant`. Returns `{:ok, course}` or
  `{:error, reason}` (e.g. not found, or a cross-tenant/unauthorized id),
  same as `get_course/2`.
  """
  def load_course_tree(course_id, opts) do
    lessons_query =
      Matwork.Curriculum.Lesson
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.load(:video)

    sections_query =
      Matwork.Curriculum.CourseSection
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.load(lessons: lessons_query)

    get_course(course_id, Keyword.put(opts, :load, sections: sections_query))
  end

  # Returns max(position)+1 among the rows matching `filter` (a keyword filter
  # like `[course_id: id]`), or 0 when there are none. Reads with the caller's
  # actor/tenant — curriculum managers can read all rows.
  @doc false
  def next_position(resource, filter, opts) do
    query =
      resource
      |> Ash.Query.filter(^filter)
      |> Ash.Query.sort(position: :desc)
      |> Ash.Query.limit(1)

    case Ash.read!(query, opts) do
      [%{position: position}] -> position + 1
      [] -> 0
    end
  end

  # Swap `record`'s position with its neighbor one slot in `direction`
  # (`:up`/`:down`) among the siblings matching `filter`. No-op at a boundary,
  # or when `direction` isn't `:up`/`:down` — this is a public domain function
  # (via reorder_section/3, reorder_lesson/3), so it must not crash on an
  # unexpected direction from a caller other than the LiveView's own
  # string-to-atom guard (which already filters bad input, but shouldn't be
  # the only thing standing between a bad atom and a FunctionClauseError).
  # `set_position_fun` is the resource's `set_*_position!` code interface.
  #
  # Re-reads `record` as `current` from the fresh `siblings` list rather than
  # trusting the caller-supplied struct's `position` field, since a caller may
  # be holding a stale copy. Both writes happen inside a DB transaction so a
  # failure between them can't leave positions duplicated/inconsistent.
  @doc false
  def swap_position(resource, filter, record, direction, set_position_fun, opts) do
    case delta(direction) do
      nil -> :ok
      delta -> do_swap_position(resource, filter, record, delta, set_position_fun, opts)
    end
  end

  defp do_swap_position(resource, filter, record, delta, set_position_fun, opts) do
    siblings =
      resource
      |> Ash.Query.filter(^filter)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(opts)

    index = Enum.find_index(siblings, &(&1.id == record.id))
    target = index && index + delta

    if is_integer(target) and target >= 0 and target < length(siblings) do
      current = Enum.at(siblings, index)
      neighbor = Enum.at(siblings, target)

      Matwork.Repo.transaction(fn ->
        set_position_fun.(current, %{position: neighbor.position}, opts)
        set_position_fun.(neighbor, %{position: current.position}, opts)
      end)
    end

    :ok
  end

  defp delta(:up), do: -1
  defp delta(:down), do: 1
  defp delta(_), do: nil
end
