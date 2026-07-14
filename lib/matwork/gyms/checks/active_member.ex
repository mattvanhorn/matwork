defmodule Matwork.Gyms.Checks.ActiveMember do
  @moduledoc """
  Policy check: does the actor have an active Membership, in the tenant the
  current request is scoped to, with one of the given roles?

  Defaults to any role (owner, instructor, or student) — i.e. "is the actor
  a member of this gym at all."
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  def describe(opts) do
    "actor has an active membership with role in #{inspect(opts[:roles] || [:owner, :instructor, :student])}"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, opts) do
    roles = opts[:roles] || [:owner, :instructor, :student]
    tenant = context.subject.tenant

    Matwork.Gyms.Membership
    |> Ash.Query.filter(user_id == ^actor.id and status == :active and role in ^roles)
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end
end
