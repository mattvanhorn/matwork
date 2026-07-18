defmodule Matwork.Curriculum.Validations.CourseInTenant do
  @moduledoc """
  Validates that a CourseSection's `course_id` resolves to a `Course` in the
  same tenant (gym_id) as the change. Prevents a curriculum manager in one
  gym from attaching a section to another gym's course by passing an
  arbitrary course_id.
  """
  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, context) do
    course_id = Ash.Changeset.get_attribute(changeset, :course_id)
    tenant = changeset.tenant

    exists? =
      Matwork.Curriculum.Course
      |> Ash.Query.filter(id == ^course_id)
      |> Ash.exists?(tenant: tenant, actor: context.actor)

    if exists? do
      :ok
    else
      {:error, field: :course_id, message: "must belong to this gym"}
    end
  end
end
