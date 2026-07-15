defmodule Matwork.Gyms.Invite.Changes.SendInviteEmail do
  @moduledoc "Emails the invite link after a successful Invite creation."
  use Ash.Resource.Change

  alias Matwork.Gyms.Invite.Senders.SendInviteEmail

  def change(changeset, _opts, context) do
    actor = context.actor

    Ash.Changeset.after_action(changeset, fn changeset, invite ->
      invite = Ash.load!(invite, :gym, tenant: changeset.tenant, actor: actor)
      SendInviteEmail.send(invite, invite.gym)
      {:ok, invite}
    end)
  end
end
