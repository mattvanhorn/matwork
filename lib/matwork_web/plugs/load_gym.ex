defmodule MatworkWeb.Plugs.LoadGym do
  @moduledoc """
  Resolves the `:slug` path param to a `Gym`, sets it as the Ash tenant on
  the conn, and assigns `:current_gym` and `:current_membership` (`nil` if
  the signed-in user, if any, has no active membership in this gym).
  Responds 404 if the slug does not resolve to a gym.
  """
  import Plug.Conn

  alias Matwork.Gyms

  def init(opts), do: opts

  def call(conn, _opts) do
    actor = conn.assigns[:current_user]

    case Gyms.get_gym_by_slug(conn.params["slug"], actor: actor) do
      {:ok, gym} ->
        conn
        |> Ash.PlugHelpers.set_tenant(gym.id)
        |> assign(:current_gym, gym)
        |> assign(:current_membership, Gyms.resolve_current_membership(actor, gym))

      {:error, _not_found} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(404, "Gym not found")
        |> halt()
    end
  end
end
