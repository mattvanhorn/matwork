defmodule Matwork.Platform.WebhookEvent do
  @moduledoc """
  Idempotent ledger of inbound provider webhooks (Mux now; Stripe in M2).
  Global resource. Recorded by the webhook controller and processed by an Oban
  job — never processed inline. Uniqueness on `(provider, external_id)` makes
  double-delivery a no-op upsert.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Platform,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "webhook_events"
    repo Matwork.Repo
  end

  actions do
    defaults [:read]

    create :record do
      accept [:provider, :external_id, :payload]
      upsert? true
      upsert_identity :unique_provider_event
      # On duplicate delivery, keep the original row untouched.
      upsert_fields []
    end

    update :mark_processed do
      accept []
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    # Only webhook-processing code (the system actor) touches this resource.
    bypass Matwork.Platform.Checks.SystemActor do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      constraints one_of: [:stripe, :mux]
      allow_nil? false
      public? true
    end

    attribute :external_id, :string do
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
      allow_nil? false
      public? true
    end

    attribute :processed_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_provider_event, [:provider, :external_id]
  end
end
