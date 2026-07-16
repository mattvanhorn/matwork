defmodule Matwork.Gyms.Checks.RosterVisible do
  @moduledoc """
  Filter check for `Matwork.Accounts.User`'s `:read` action: an actor may
  read a target User if the actor holds an active owner/instructor
  membership in the tenant (gym) the current request is scoped to, AND
  the target User also holds an active membership in that same gym.

  Used to scope gym-roster visibility to owners/instructors of THAT
  specific gym — not "an owner/instructor of any gym can read any user,"
  which was the gap this check closes (see commit f022f71's follow-up).
  """
  use Ash.Policy.FilterCheck

  def describe(opts) do
    "actor has an active membership with role in #{inspect(opts[:roles] || [:owner, :instructor])} in the same gym the target user is also an active member of"
  end

  def filter(_actor, _authorizer, opts) do
    roles = opts[:roles] || [:owner, :instructor]

    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and role in ^roles and gym_id == ^tenant()
      ) and
        exists(
          Matwork.Gyms.Membership,
          user_id == parent(id) and status == :active and gym_id == ^tenant()
        )
    )
  end
end
