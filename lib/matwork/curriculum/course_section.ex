defmodule Matwork.Curriculum.CourseSection do
  @moduledoc """
  A section within a course: an ordered grouping of lessons. Tenant-scoped
  on `gym_id`.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "course_sections"
    repo Matwork.Repo

    references do
      reference :course, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:course_id, :title, :position]
    end

    update :update do
      accept [:title]
    end

    update :set_position do
      accept [:position]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Matwork.Curriculum.Checks.SectionVisible
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

    belongs_to :course, Matwork.Curriculum.Course do
      allow_nil? false
      public? true
    end
  end
end
