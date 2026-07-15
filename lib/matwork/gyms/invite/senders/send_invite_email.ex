defmodule Matwork.Gyms.Invite.Senders.SendInviteEmail do
  @moduledoc "Sends an email inviting someone to join a gym."
  use MatworkWeb, :verified_routes

  import Swoosh.Email
  alias Matwork.Mailer

  def send(invite, gym) do
    new()
    |> from({"noreply", "matt@stalwartstudios.com"})
    |> to(to_string(invite.email))
    |> subject("You're invited to join #{gym.name}")
    |> html_body(body(invite: invite, gym: gym))
    |> Mailer.deliver!()
  end

  defp body(params) do
    invite = params[:invite]
    gym = params[:gym]

    """
    <p>You've been invited to join #{gym.name} on Matwork as a #{invite.role}.</p>
    <p><a href="#{url(~p"/g/#{gym.slug}/invite/#{invite.token}")}">Accept your invite</a></p>
    """
  end
end
