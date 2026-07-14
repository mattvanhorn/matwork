defmodule Matwork.Gyms.Membership do
  @moduledoc """
  A user's membership in a gym: their role and status on the roster.
  Tenant-scoped on `gym_id`.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Gyms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "memberships"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :create_owner do
      accept [:user_id]
      change set_attribute(:role, :owner)
      change set_attribute(:status, :active)
    end

    update :remove do
      accept []
      change set_attribute(:status, :removed)
    end
  end

  policies do
    policy action(:create_owner) do
      authorize_if expr(gym.owner_id == ^actor(:id))
    end

    policy action_type(:read) do
      authorize_if Matwork.Gyms.Checks.ActiveMember
    end

    policy action(:remove) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:owner, :instructor, :student]
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:active, :invited, :removed]
      default :active
      allow_nil? false
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :gym, Matwork.Gyms.Gym do
      allow_nil? false
      public? true
    end

    belongs_to :user, Matwork.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_user_per_gym, [:user_id]
  end
end
