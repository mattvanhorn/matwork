defmodule Matwork.Gyms.Checks.CanRemoveMembership do
  @moduledoc """
  Policy check for `Membership.remove`: an owner can remove anyone's
  membership; an instructor can only remove a student's membership.
  """
  use Ash.Policy.SimpleCheck

  alias Matwork.Gyms.Checks.ActiveMember

  def describe(_opts) do
    "actor is an active owner, or an active instructor removing a student's membership"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    cond do
      ActiveMember.match?(actor, context, roles: [:owner]) ->
        true

      context.subject.data.role == :student ->
        ActiveMember.match?(actor, context, roles: [:instructor])

      true ->
        false
    end
  end
end
