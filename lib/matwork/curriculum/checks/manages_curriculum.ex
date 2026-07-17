defmodule Matwork.Curriculum.Checks.ManagesCurriculum do
  @moduledoc """
  Policy check: does the actor hold an active `:owner` or `:instructor`
  Membership in the tenant the current request is scoped to? Gates every
  write action on the Curriculum resources.

  Mirrors `Matwork.Gyms.Checks.ActiveMember`, narrowed to the two roles
  that may build curriculum.
  """
  use Ash.Policy.SimpleCheck

  require Ash.Query

  def describe(_opts) do
    "actor has an active owner/instructor membership in this gym"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    tenant = context.subject.tenant

    Matwork.Gyms.Membership
    |> Ash.Query.filter(
      user_id == ^actor.id and status == :active and role in [:owner, :instructor]
    )
    |> Ash.exists?(tenant: tenant, authorize?: false)
  end
end
