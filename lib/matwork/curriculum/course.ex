defmodule Matwork.Curriculum.Course do
  @moduledoc """
  A gym's course: the root of the curriculum tree. Tenant-scoped on `gym_id`.
  `status` drives student visibility (see `Checks.CourseVisible`); ordering is
  a plain integer `position`.
  """
  use Ash.Resource,
    otp_app: :matwork,
    domain: Matwork.Curriculum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "courses"
    repo Matwork.Repo

    custom_indexes do
      index [:gym_id]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title, :description, :position]
    end

    update :update do
      accept [:title, :description]
    end

    update :set_position do
      accept [:position]
    end

    update :publish do
      accept []
      change set_attribute(:status, :published)
    end

    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end

    update :unarchive do
      accept []
      change set_attribute(:status, :draft)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if Matwork.Curriculum.Checks.CourseVisible
    end

    policy action_type([:create, :update]) do
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

    attribute :status, :atom do
      constraints one_of: [:draft, :published, :archived]
      default :draft
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

    has_many :sections, Matwork.Curriculum.CourseSection do
      destination_attribute :course_id
    end
  end
end
