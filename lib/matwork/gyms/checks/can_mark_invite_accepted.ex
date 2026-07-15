defmodule Matwork.Gyms.Checks.CanMarkInviteAccepted do
  @moduledoc """
  Policy check for `Invite.mark_accepted`: only the actor whose email
  matches the invite may mark it accepted, and only while it is still
  unaccepted. Mirrors the email-match guard enforced in
  `Membership.Changes.AcceptInvite`.
  """
  use Ash.Policy.SimpleCheck

  def describe(_opts) do
    "actor's email matches the invite's email, and the invite is not already accepted"
  end

  def match?(nil, _context, _opts), do: false

  def match?(actor, context, _opts) do
    invite = context.subject.data

    is_nil(invite.accepted_at) and Ash.CiString.compare(actor.email, invite.email) == :eq
  end
end
