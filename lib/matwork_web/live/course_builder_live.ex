defmodule MatworkWeb.CourseBuilderLive do
  use MatworkWeb, :live_view

  import StalwartUI.CurriculumTree

  alias Matwork.Curriculum
  alias MatworkWeb.GymLiveAuth

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(%{"id" => course_id}, _session, socket) do
    membership = socket.assigns.current_membership

    if GymLiveAuth.manager?(membership) do
      case Curriculum.load_course_tree(course_id, opts(socket)) do
        {:ok, course} ->
          {:ok, socket |> assign(:course_id, course_id) |> assign_course(course)}

        {:error, _not_found} ->
          {:ok,
           socket
           |> put_flash(:error, "Course not found.")
           |> push_navigate(to: ~p"/g/#{socket.assigns.current_gym.slug}/courses")}
      end
    else
      {:ok, assign(socket, manager?: false, course: nil, sections: [], raw_sections: [])}
    end
  end

  # --- section events ---

  def handle_event("add_section", %{"title" => title}, socket) do
    case Curriculum.add_section(socket.assigns.course, title, opts(socket)) do
      {:ok, _section} ->
        {:noreply, load_course(socket)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Could not add section.") |> load_course()}
    end
  end

  def handle_event("rename_section", %{"_id" => id, "title" => title}, socket) do
    with_section(socket, id, fn section ->
      case Curriculum.update_section(section, %{title: title}, opts(socket)) do
        {:ok, _} ->
          load_course(socket)

        {:error, _} ->
          socket |> put_flash(:error, "Could not save — title can't be blank.") |> load_course()
      end
    end)
  end

  def handle_event("delete_section", %{"id" => id}, socket) do
    with_section(socket, id, fn section ->
      case Curriculum.destroy_section(section, opts(socket)) do
        :ok -> load_course(socket)
        {:ok, _} -> load_course(socket)
        {:error, _} -> socket |> put_flash(:error, "Could not delete section.") |> load_course()
      end
    end)
  end

  def handle_event("move_section", %{"id" => id, "direction" => direction}, socket) do
    with_section(socket, id, fn section ->
      case to_direction(direction) do
        nil ->
          load_course(socket)

        direction ->
          Curriculum.reorder_section(section, direction, opts(socket))
          load_course(socket)
      end
    end)
  end

  # --- lesson events ---

  def handle_event("add_lesson", %{"_id" => section_id, "title" => title}, socket) do
    with_section(socket, section_id, fn section ->
      case Curriculum.add_lesson(section, title, opts(socket)) do
        {:ok, _lesson} ->
          load_course(socket)

        {:error, _} ->
          socket |> put_flash(:error, "Could not add lesson.") |> load_course()
      end
    end)
  end

  def handle_event("rename_lesson", %{"_id" => id, "title" => title}, socket) do
    with_lesson(socket, id, fn lesson ->
      case Curriculum.update_lesson(lesson, %{title: title}, opts(socket)) do
        {:ok, _} ->
          load_course(socket)

        {:error, _} ->
          socket |> put_flash(:error, "Could not save — title can't be blank.") |> load_course()
      end
    end)
  end

  def handle_event("delete_lesson", %{"id" => id}, socket) do
    with_lesson(socket, id, fn lesson ->
      case Curriculum.destroy_lesson(lesson, opts(socket)) do
        :ok -> load_course(socket)
        {:ok, _} -> load_course(socket)
        {:error, _} -> socket |> put_flash(:error, "Could not delete lesson.") |> load_course()
      end
    end)
  end

  def handle_event("move_lesson", %{"id" => id, "direction" => direction}, socket) do
    with_lesson(socket, id, fn lesson ->
      case to_direction(direction) do
        nil ->
          load_course(socket)

        direction ->
          Curriculum.reorder_lesson(lesson, direction, opts(socket))
          load_course(socket)
      end
    end)
  end

  def handle_event("toggle_preview", %{"id" => id}, socket) do
    with_lesson(socket, id, fn lesson ->
      case Curriculum.set_lesson_preview(lesson, !lesson.free_preview, opts(socket)) do
        {:ok, _} ->
          load_course(socket)

        {:error, _} ->
          socket |> put_flash(:error, "Could not update preview.") |> load_course()
      end
    end)
  end

  # --- course status events ---

  def handle_event("publish", _params, socket) do
    case Curriculum.publish_course(socket.assigns.course, opts(socket)) do
      {:ok, _} ->
        {:noreply, load_course(socket)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Could not publish course.") |> load_course()}
    end
  end

  def handle_event("archive", _params, socket) do
    case Curriculum.archive_course(socket.assigns.course, opts(socket)) do
      {:ok, _} ->
        {:noreply, load_course(socket)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Could not archive course.") |> load_course()}
    end
  end

  def handle_event("unarchive", _params, socket) do
    case Curriculum.unarchive_course(socket.assigns.course, opts(socket)) do
      {:ok, _} ->
        {:noreply, load_course(socket)}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Could not unarchive course.") |> load_course()}
    end
  end

  # --- helpers ---

  defp opts(socket) do
    gym = socket.assigns.current_gym
    [actor: socket.assigns.current_user, tenant: gym.id]
  end

  defp to_direction("up"), do: :up
  defp to_direction("down"), do: :down
  defp to_direction(_), do: nil

  # Looks up a section/lesson by id from the last-loaded tree and runs `fun`
  # with it. A `nil` lookup means the id came from a stale DOM (deleted by
  # someone else, or a concurrent edit) — flash and reload instead of
  # calling a domain function with `nil`.
  defp with_section(socket, id, fun) do
    case find_section(socket, id) do
      nil -> {:noreply, stale_item(socket)}
      section -> {:noreply, fun.(section)}
    end
  end

  defp with_lesson(socket, id, fun) do
    case find_lesson(socket, id) do
      nil -> {:noreply, stale_item(socket)}
      lesson -> {:noreply, fun.(lesson)}
    end
  end

  defp stale_item(socket) do
    socket
    |> put_flash(:error, "That item no longer exists — refreshing.")
    |> load_course()
  end

  defp find_section(socket, id), do: Enum.find(socket.assigns.raw_sections, &(&1.id == id))

  defp find_lesson(socket, id) do
    socket.assigns.raw_sections
    |> Enum.flat_map(& &1.lessons)
    |> Enum.find(&(&1.id == id))
  end

  # Reloads the course tree after a write and re-assigns it. Assumes the
  # course still exists (it did a moment ago); a concurrent full-course
  # deletion mid-session is out of scope for this POC.
  defp load_course(socket) do
    {:ok, course} = Curriculum.load_course_tree(socket.assigns.course_id, opts(socket))
    assign_course(socket, course)
  end

  # Keeps the raw Ash structs (for event handlers' find_section/find_lesson)
  # and a plain-map projection (for the CurriculumTree component).
  defp assign_course(socket, course) do
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
