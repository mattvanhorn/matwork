defmodule MatworkWeb.CourseIndexLive do
  use MatworkWeb, :live_view

  alias Matwork.Curriculum

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(_params, _session, socket) do
    {:ok, assign_courses(socket)}
  end

  def handle_event("create_course", %{"form" => %{"title" => title}}, socket) do
    gym = socket.assigns.current_gym

    case Curriculum.add_course(gym.id, title,
           actor: socket.assigns.current_user,
           tenant: gym.id
         ) do
      {:ok, _course} ->
        {:noreply, socket |> put_flash(:info, "Course created") |> assign_courses()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create course")}
    end
  end

  defp assign_courses(socket) do
    gym = socket.assigns.current_gym
    membership = socket.assigns.current_membership

    if manager?(membership) do
      courses =
        Curriculum.list_courses!(actor: socket.assigns.current_user, tenant: gym.id)
        |> Enum.sort_by(& &1.position)

      assign(socket, courses: courses, manager?: true)
    else
      assign(socket, courses: [], manager?: false)
    end
  end

  defp manager?(nil), do: false
  defp manager?(membership), do: membership.role in [:owner, :instructor]

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
      <.header>Courses</.header>

      <div :if={!@manager?}>
        <p>You don't have access to manage this gym's curriculum.</p>
      </div>

      <div :if={@manager?}>
        <ul id="course-list" class="space-y-2">
          <li :for={course <- @courses} id={"course-#{course.id}"}>
            <.link navigate={~p"/g/#{@current_gym.slug}/courses/#{course.id}/edit"}>
              {course.title}
            </.link>
            <span class="badge badge-sm">{course.status}</span>
          </li>
        </ul>
        <p :if={@courses == []} class="text-sm opacity-70">No courses yet.</p>

        <form id="new-course-form" phx-submit="create_course" class="mt-4 flex items-center gap-2">
          <input
            type="text"
            name="form[title]"
            placeholder="New course title"
            class="input input-bordered"
          />
          <button type="submit" class="btn btn-primary">Create course</button>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
