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

    custom_indexes do
      # AshPostgres prepends the multitenancy attribute (gym_id) to declared
      # indexes on attribute-multitenant resources, so this alone already
      # produces a [:gym_id, :course_id] index — a separate [:gym_id]-only
      # index would be redundant (Postgres can use this one's leftmost
      # prefix for gym_id-only queries).
      index [:course_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:course_id, :title, :position]
      validate {Matwork.Curriculum.Validations.CourseInTenant, []}
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

    has_many :lessons, Matwork.Curriculum.Lesson do
      destination_attribute :section_id
    end
  end
end
