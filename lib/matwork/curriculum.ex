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
    end
  end

  @doc """
  Create a course at the end of the gym's course list (next `position`).
  `opts` must include `:actor` and `:tenant`.
  """
  def add_course(_gym_id, title, opts) do
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
  # (`:up`/`:down`) among the siblings matching `filter`. No-op at a boundary.
  # `set_position_fun` is the resource's `set_*_position!` code interface.
  #
  # Re-reads `record` as `current` from the fresh `siblings` list rather than
  # trusting the caller-supplied struct's `position` field, since a caller may
  # be holding a stale copy. Both writes happen inside a DB transaction so a
  # failure between them can't leave positions duplicated/inconsistent.
  @doc false
  def swap_position(resource, filter, record, direction, set_position_fun, opts) do
    siblings =
      resource
      |> Ash.Query.filter(^filter)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(opts)

    index = Enum.find_index(siblings, &(&1.id == record.id))
    target = index && index + delta(direction)

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
end
