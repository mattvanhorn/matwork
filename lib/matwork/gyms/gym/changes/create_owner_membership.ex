defmodule Matwork.Gyms.Gym.Changes.CreateOwnerMembership do
  @moduledoc """
  After a gym is created, creates the owner's Membership row in the same
  transaction. Runs as an `after_action` hook so the new gym's id is
  available to use as the tenant.
  """
  use Ash.Resource.Change

  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, gym ->
      case Matwork.Gyms.create_owner_membership(gym.owner_id,
             actor: context.actor,
             tenant: gym.id
           ) do
        {:ok, _membership} -> {:ok, gym}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
