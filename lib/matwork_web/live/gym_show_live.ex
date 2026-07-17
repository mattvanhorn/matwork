defmodule MatworkWeb.GymShowLive do
  use MatworkWeb, :live_view

  import StalwartUI.RosterTable
  import StalwartUI.InviteForm

  alias Matwork.Gyms

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(_params, _session, socket) do
    {:ok, assign_roster_and_form(socket)}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply,
     assign(socket, :invite_form, AshPhoenix.Form.validate(socket.assigns.invite_form, params))}
  end

  def handle_event("invite", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.invite_form, params: params) do
      {:ok, _invite} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invite sent")
         |> assign_roster_and_form()}

      {:error, form} ->
        {:noreply, assign(socket, :invite_form, form)}
    end
  end

  defp assign_roster_and_form(socket) do
    gym = socket.assigns.current_gym
    actor = socket.assigns.current_user
    membership = socket.assigns.current_membership

    if membership && membership.role in [:owner, :instructor] do
      memberships =
        Gyms.list_memberships!(
          actor: actor,
          tenant: gym.id,
          query: [filter: [status: :active]],
          load: [:user]
        )

      invite_form = Gyms.form_to_create_invite(actor: actor, tenant: gym.id) |> to_form()

      socket
      |> assign(:memberships, memberships)
      |> assign(:invite_form, invite_form)
    else
      socket
      |> assign(:memberships, [])
      |> assign(:invite_form, nil)
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
      <.header>{@current_gym.name}</.header>

      <div :if={is_nil(@current_membership)}>
        <p>You don't have access to this gym yet.</p>
      </div>

      <div :if={@current_membership && @current_membership.role in [:owner, :instructor]}>
        <.roster_table id="roster" memberships={@memberships} />

        <div :if={@invite_form}>
          <.invite_form form={@invite_form} />
        </div>
      </div>

      <div :if={@current_membership && @current_membership.role == :student} id="student-view">
        <p>You're a member of {@current_gym.name}.</p>
      </div>
    </Layouts.app>
    """
  end
end
