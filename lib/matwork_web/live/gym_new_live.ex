defmodule MatworkWeb.GymNewLive do
  use MatworkWeb, :live_view

  alias Matwork.Gyms

  on_mount {MatworkWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    form = Gyms.form_to_create_gym(actor: socket.assigns.current_user) |> to_form()
    {:ok, assign(socket, :form, form)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, gym} ->
        {:noreply, push_navigate(socket, to: ~p"/g/#{gym.slug}")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>Create a gym</.header>
      <.form for={@form} id="gym-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="Gym name" />
        <.input field={@form[:slug]} type="text" label="URL slug" />
        <.button variant="primary">Create gym</.button>
      </.form>
    </Layouts.app>
    """
  end
end
