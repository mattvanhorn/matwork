defmodule Matwork.Media.Video do
  @moduledoc """
  A Mux-backed video. Tenant-scoped on `gym_id`. Created in `:pending_upload`
  when an instructor starts a direct upload; driven to `:processing`/`:ready`/
  `:errored` by webhook-processing jobs running as the system actor. Playback
  IDs are signed-policy; minting playback JWTs is Session 3, not here.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Media,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "videos"
    repo Matwork.Repo

    custom_indexes do
      index [:gym_id]
      index [:mux_upload_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:mux_upload_id, :title]
      change relate_actor(:uploaded_by)
    end

    read :by_upload_id do
      argument :mux_upload_id, :string, allow_nil?: false
      get? true
      filter expr(mux_upload_id == ^arg(:mux_upload_id))
    end

    update :mark_processing do
      accept [:mux_asset_id]
      change set_attribute(:status, :processing)
    end

    update :mark_ready do
      accept [:mux_asset_id, :mux_playback_id, :duration_seconds]
      change set_attribute(:status, :ready)
    end

    update :mark_errored do
      accept []
      change set_attribute(:status, :errored)
    end
  end

  policies do
    # Webhook jobs (system actor) may do anything, including the mark_* writes.
    bypass Matwork.Platform.Checks.SystemActor do
      authorize_if always()
    end

    policy action_type([:create, :read]) do
      authorize_if {Matwork.Gyms.Checks.ActiveMember, roles: [:owner, :instructor]}
    end

    # mark_* updates have no non-system policy → forbidden for everyone else.
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      public? true
    end

    attribute :mux_upload_id, :string do
      allow_nil? false
      public? true
    end

    attribute :mux_asset_id, :string do
      public? true
    end

    attribute :mux_playback_id, :string do
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:pending_upload, :processing, :ready, :errored]
      default :pending_upload
      allow_nil? false
      public? true
    end

    attribute :duration_seconds, :integer do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :gym, Matwork.Gyms.Gym do
      allow_nil? false
      public? true
    end

    belongs_to :uploaded_by, Matwork.Accounts.User do
      allow_nil? false
      public? true
    end
  end
end
