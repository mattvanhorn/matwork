defmodule Matwork.Gyms.Invite do
  @moduledoc """
  An email invitation to join a gym with a given role. Tenant-scoped on
  `gym_id`. Accepting an invite is gated by possessing the random `token`
  (see `Matwork.Gyms.Membership`'s `:accept_invite` action), the same
  trust model this codebase already uses for magic-link sign-in.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Gyms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "invites"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:email, :role]
      change Matwork.Gyms.Invite.Changes.GenerateToken
      change Matwork.Gyms.Invite.Changes.SendInviteEmail
    end

    read :get_by_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(token == ^arg(:token))
    end

    update :mark_accepted do
      accept []
      change set_attribute(:accepted_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if Matwork.Gyms.Checks.CanInviteRole
    end

    policy action(:read) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end

    # Token possession is the credential here, mirroring the existing
    # magic-link sign-in pattern in Matwork.Accounts.User — the invited
    # person does not have a Membership yet, so an ActiveMember check
    # can never pass for them.
    policy action(:get_by_token) do
      authorize_if always()
    end

    policy action(:mark_accepted) do
      authorize_if Matwork.Gyms.Checks.CanMarkInviteAccepted
    end
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :role, :atom do
      constraints one_of: [:owner, :instructor, :student]
      allow_nil? false
      public? true
    end

    attribute :token, :string do
      allow_nil? false
      writable? false
      public? true
    end

    attribute :accepted_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :gym, Matwork.Gyms.Gym do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_token, [:token]
  end
end
