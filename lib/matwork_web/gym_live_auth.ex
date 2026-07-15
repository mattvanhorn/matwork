defmodule MatworkWeb.GymLiveAuth do
  @moduledoc """
  `on_mount` hook for LiveViews scoped under `/g/:slug`. Resolves the
  `:slug` path param to a `Gym` and the actor's `Membership`, assigning
  `:current_gym`/`:current_membership` on the socket.

  Must be declared *after* `{MatworkWeb.LiveUserAuth, :live_user_optional}`
  (or `:live_user_required`) in a LiveView's `on_mount` list, since it
  reads `socket.assigns[:current_user]`.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  use MatworkWeb, :verified_routes

  alias Matwork.Gyms

  def on_mount(:default, %{"slug" => slug}, _session, socket) do
    actor = socket.assigns[:current_user]

    case Gyms.get_gym_by_slug(slug, actor: actor) do
      {:ok, gym} ->
        {:cont,
         socket
         |> assign(:current_gym, gym)
         |> assign(:current_membership, Gyms.resolve_current_membership(actor, gym))}

      {:error, _not_found} ->
        {:halt,
         socket
         |> put_flash(:error, "Gym not found")
         |> redirect(to: ~p"/")}
    end
  end
end
