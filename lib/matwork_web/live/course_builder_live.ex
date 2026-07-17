defmodule MatworkWeb.CourseBuilderLive do
  use MatworkWeb, :live_view

  import StalwartUI.CurriculumTree

  alias Matwork.Curriculum

  require Ash.Query

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(%{"id" => course_id}, _session, socket) do
    membership = socket.assigns.current_membership

    if manager?(membership) do
      {:ok, socket |> assign(:course_id, course_id) |> load_course()}
    else
      {:ok, assign(socket, manager?: false, course: nil, sections: [])}
    end
  end

  # --- section events ---

  def handle_event("add_section", %{"title" => title}, socket) do
    Curriculum.add_section(socket.assigns.course, title, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("rename_section", %{"_id" => id, "title" => title}, socket) do
    section = find_section(socket, id)
    Curriculum.update_section(section, %{title: title}, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("delete_section", %{"id" => id}, socket) do
    section = find_section(socket, id)
    Curriculum.destroy_section(section, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("move_section", %{"id" => id, "direction" => direction}, socket) do
    section = find_section(socket, id)
    Curriculum.reorder_section(section, to_direction(direction), opts(socket))
    {:noreply, load_course(socket)}
  end

  # --- lesson events ---

  def handle_event("add_lesson", %{"_id" => section_id, "title" => title}, socket) do
    section = find_section(socket, section_id)
    Curriculum.add_lesson(section, title, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("rename_lesson", %{"_id" => id, "title" => title}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.update_lesson(lesson, %{title: title}, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("delete_lesson", %{"id" => id}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.destroy_lesson(lesson, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("move_lesson", %{"id" => id, "direction" => direction}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.reorder_lesson(lesson, to_direction(direction), opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("toggle_preview", %{"id" => id}, socket) do
    lesson = find_lesson(socket, id)
    Curriculum.set_lesson_preview(lesson, !lesson.free_preview, opts(socket))
    {:noreply, load_course(socket)}
  end

  # --- course status events ---

  def handle_event("publish", _params, socket) do
    Curriculum.publish_course(socket.assigns.course, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("archive", _params, socket) do
    Curriculum.archive_course(socket.assigns.course, opts(socket))
    {:noreply, load_course(socket)}
  end

  def handle_event("unarchive", _params, socket) do
    Curriculum.unarchive_course(socket.assigns.course, opts(socket))
    {:noreply, load_course(socket)}
  end

  # --- helpers ---

  defp opts(socket) do
    gym = socket.assigns.current_gym
    [actor: socket.assigns.current_user, tenant: gym.id]
  end

  defp manager?(nil), do: false
  defp manager?(membership), do: membership.role in [:owner, :instructor]

  defp to_direction("up"), do: :up
  defp to_direction("down"), do: :down

  defp find_section(socket, id), do: Enum.find(socket.assigns.raw_sections, &(&1.id == id))

  defp find_lesson(socket, id) do
    socket.assigns.raw_sections
    |> Enum.flat_map(& &1.lessons)
    |> Enum.find(&(&1.id == id))
  end

  # Loads the course with sections (sorted) each loading lessons (sorted).
  # Keeps the raw Ash structs (for event handlers) and a plain-map projection
  # (for the CurriculumTree component).
  defp load_course(socket) do
    lessons_query = Ash.Query.sort(Matwork.Curriculum.Lesson, position: :asc)

    sections_query =
      Matwork.Curriculum.CourseSection
      |> Ash.Query.sort(position: :asc)
      |> Ash.Query.load(lessons: lessons_query)

    course =
      Curriculum.get_course!(
        socket.assigns.course_id,
        Keyword.put(opts(socket), :load, sections: sections_query)
      )

    raw_sections = course.sections

    tree_sections =
      Enum.map(raw_sections, fn section ->
        %{
          id: section.id,
          title: section.title,
          lessons:
            Enum.map(section.lessons, fn lesson ->
              %{id: lesson.id, title: lesson.title, free_preview: lesson.free_preview}
            end)
        }
      end)

    assign(socket,
      course: course,
      raw_sections: raw_sections,
      sections: tree_sections,
      manager?: true
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
      <div :if={!@manager?}>
        <p>You don't have access to manage this gym's curriculum.</p>
      </div>

      <div :if={@manager?}>
        <.header>
          {@course.title}
          <span class="badge">{@course.status}</span>
          <:actions>
            <button phx-click="publish" class="btn btn-sm btn-primary">Publish</button>
            <button phx-click="archive" class="btn btn-sm">Archive</button>
            <button phx-click="unarchive" class="btn btn-sm">Unarchive</button>
          </:actions>
        </.header>

        <.curriculum_tree sections={@sections} />
      </div>
    </Layouts.app>
    """
  end
end
