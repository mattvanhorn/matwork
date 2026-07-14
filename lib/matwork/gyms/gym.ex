defmodule Matwork.Gyms.Gym do
  @moduledoc """
  A gym: the tenant root. Global resource — a gym's own row is not itself
  scoped to a tenant, and its slug must be resolvable by unauthenticated
  visitors (see the tenant-resolution plug planned for a later session).
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Gyms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "gyms"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :slug]
      change relate_actor(:owner)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :custom_domain, :ci_string do
      public? true
    end

    attribute :stripe_account_id, :string do
      public? true
    end

    attribute :stripe_onboarding_state, :atom do
      constraints one_of: [:none, :started, :complete]
      default :none
      allow_nil? false
      public? true
    end

    attribute :application_fee_percent, :decimal do
      allow_nil? false
      default fn -> Application.get_env(:matwork, :default_application_fee_percent) end
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :owner, Matwork.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
    identity :unique_custom_domain, [:custom_domain]
  end
end
