defmodule Matwork.Curriculum.Lesson do
  @moduledoc """
  A lesson within a section. Tenant-scoped on `gym_id`. `free_preview` marks a
  lesson as watchable without payment (playback gating lands in Session 3).
  A `video_id` relationship is added in Session 2 with the Media domain.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lessons"
    repo Matwork.Repo

    references do
      reference :section, on_delete: :delete
    end

    custom_indexes do
      index [:gym_id]
      index [:section_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:section_id, :title, :description, :free_preview, :position]
      validate {Matwork.Curriculum.Validations.SectionInTenant, []}
    end

    update :update do
      accept [:title, :description, :free_preview]
    end

    update :set_position do
      accept [:position]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Matwork.Curriculum.Checks.LessonVisible
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if Matwork.Curriculum.Checks.ManagesCurriculum
    end
  end

  multitenancy do
    strategy :attribute
    attribute :gym_id
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :free_preview, :boolean do
      default false
      allow_nil? false
      public? true
    end

    attribute :position, :integer do
      default 0
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

    belongs_to :section, Matwork.Curriculum.CourseSection do
      allow_nil? false
      public? true
    end
  end
end
