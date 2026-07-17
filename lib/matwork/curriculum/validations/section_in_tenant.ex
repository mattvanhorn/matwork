defmodule Matwork.Curriculum.Validations.SectionInTenant do
  @moduledoc """
  Validates that a Lesson's `section_id` resolves to a `CourseSection` in the
  same tenant (gym_id) as the change. Prevents a curriculum manager in one
  gym from attaching a lesson to another gym's section by passing an
  arbitrary section_id.
  """
  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    section_id = Ash.Changeset.get_attribute(changeset, :section_id)
    tenant = changeset.tenant

    exists? =
      Matwork.Curriculum.CourseSection
      |> Ash.Query.filter(id == ^section_id)
      |> Ash.exists?(tenant: tenant, authorize?: false)

    if exists? do
      :ok
    else
      {:error, field: :section_id, message: "must belong to this gym"}
    end
  end
end
