defmodule MatworkWeb.InviteAcceptLive do
  use MatworkWeb, :live_view

  alias Matwork.Gyms

  on_mount {MatworkWeb.LiveUserAuth, :live_user_optional}
  on_mount {MatworkWeb.GymLiveAuth, :default}

  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, token: token, status: nil)

    {:ok, resolve(socket)}
  end

  defp resolve(socket) do
    gym = socket.assigns.current_gym

    case socket.assigns.current_user do
      nil ->
        assign(socket, :status, :needs_sign_in)

      user ->
        case Gyms.accept_invite(socket.assigns.token, actor: user, tenant: gym.id) do
          {:ok, _membership} ->
            socket
            |> put_flash(:info, "Welcome to #{gym.name}!")
            |> push_navigate(to: ~p"/g/#{gym.slug}")

          {:error, _error} ->
            assign(socket, :status, :invalid)
        end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} current_gym={@current_gym}>
      <.header>Join {@current_gym.name}</.header>

      <div :if={@status == :needs_sign_in} id="invite-needs-sign-in">
        <p>You've been invited to join {@current_gym.name}. Sign in to accept.</p>
        <.link navigate={~p"/sign-in"} class="btn btn-primary">Sign in</.link>
        <p class="text-sm mt-2">After signing in, come back to this link to finish joining.</p>
      </div>

      <div :if={@status == :invalid} id="invite-invalid">
        <p>This invite link is invalid, expired, or already used.</p>
      </div>
    </Layouts.app>
    """
  end
end
