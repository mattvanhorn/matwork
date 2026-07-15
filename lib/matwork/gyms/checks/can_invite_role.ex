defmodule Matwork.Gyms.Checks.CanInviteRole do
  @moduledoc """
  Policy check for `Invite.create`: an owner may invite anyone (owner,
  instructor, or student); an instructor may only invite a student.
  """
  use Ash.Policy.SimpleCheck

  alias Matwork.Gyms.Checks.ActiveMember

  def describe(_opts) do
    "actor is an active owner, or an active instructor inviting a student"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    cond do
      ActiveMember.match?(actor, context, roles: [:owner]) ->
        true

      Ash.Changeset.get_attribute(context.subject, :role) == :student ->
        ActiveMember.match?(actor, context, roles: [:instructor])

      true ->
        false
    end
  end
end
