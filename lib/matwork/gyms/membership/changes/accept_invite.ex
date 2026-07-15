defmodule Matwork.Gyms.Membership.Changes.AcceptInvite do
  @moduledoc """
  Looks up the Invite by its token (in the current tenant), and if it's
  valid and unused, sets this Membership's user_id/role from it and marks
  the Invite accepted. Upserts on the `unique_user_per_gym` identity, so a
  previously-removed member re-accepting an invite is reactivated.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    token = Ash.Changeset.get_argument(changeset, :token)
    tenant = changeset.tenant
    actor = context.actor

    changeset
    |> Ash.Changeset.before_action(fn changeset ->
      apply_invite(changeset, token, actor, tenant)
    end)
    |> Ash.Changeset.after_action(fn changeset, membership ->
      finalize_invite(changeset, membership, actor, tenant)
    end)
  end

  defp apply_invite(changeset, token, actor, tenant) do
    case Matwork.Gyms.get_invite_by_token(token, actor: actor, tenant: tenant) do
      {:ok, %{accepted_at: nil} = invite} ->
        if Ash.CiString.compare(actor.email, invite.email) == :eq do
          changeset
          |> Ash.Changeset.force_change_attribute(:user_id, actor.id)
          |> Ash.Changeset.force_change_attribute(:role, invite.role)
          |> Ash.Changeset.force_change_attribute(:status, :active)
          |> Ash.Changeset.put_context(:invite, invite)
        else
          Ash.Changeset.add_error(changeset,
            field: :token,
            message: "invite email does not match the signed-in account"
          )
        end

      {:ok, _already_accepted} ->
        Ash.Changeset.add_error(changeset,
          field: :token,
          message: "invite has already been accepted"
        )

      {:error, _not_found} ->
        Ash.Changeset.add_error(changeset, field: :token, message: "invalid invite token")
    end
  end

  defp finalize_invite(changeset, membership, actor, tenant) do
    case changeset.context[:invite] do
      nil ->
        {:ok, membership}

      invite ->
        mark_invite_accepted(invite, membership, actor, tenant)
    end
  end

  defp mark_invite_accepted(invite, membership, actor, tenant) do
    case Matwork.Gyms.mark_invite_accepted(invite, actor: actor, tenant: tenant) do
      {:ok, _invite} -> {:ok, membership}
      {:error, error} -> {:error, error}
    end
  end
end
