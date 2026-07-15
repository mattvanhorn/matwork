defmodule Matwork.Accounts.User do
  @moduledoc "A platform user, authenticated via magic link. Global resource — one account per email, not tenant-scoped."
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Matwork.Accounts.Token
      signing_secret Matwork.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender Matwork.Accounts.User.Senders.SendMagicLinkEmail
      end

      remember_me :remember_me
    end
  end

  postgres do
    table "users"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      change {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
              strategy_name: :remember_me}

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Reading a User is restricted to: the actor reading their own record,
    # or an actor with an active owner/instructor membership in some gym
    # (needed so GymShowLive's roster can load Membership.user for owners
    # and instructors). Deliberately NOT open to students: showing member
    # emails to fellow students risks harassment/stalking between gym
    # members, so roster visibility — and this read policy — is
    # owner/instructor-only. Note this check is not scoped to "the same
    # gym as the User being read" (User has no gym concept at this layer);
    # it's "does the actor hold an owner/instructor role in some gym."
    # Acceptable for this POC since User only exposes :id/:email — revisit
    # if that changes.
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
