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
  end

  @doc """
  Create a course at the end of the gym's course list (next `position`).
  `opts` must include `:actor` and `:tenant`.
  """
  def add_course(_gym_id, title, opts) do
    position = next_position(Matwork.Curriculum.Course, [], opts)
    create_course(title, %{position: position}, opts)
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
end
