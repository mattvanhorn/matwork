defmodule Matwork.Curriculum.Checks.SectionVisible do
  @moduledoc """
  Filter check for `CourseSection`'s `:read` action: readable if the actor
  manages curriculum in this gym, or the section's course is `:published` and
  the actor is any active member. Mirrors `Checks.CourseVisible`, reaching
  through the `course` relationship for the published branch.
  """
  use Ash.Policy.FilterCheck

  def describe(_opts) do
    "section's course is published (for active members), or actor manages curriculum in this gym"
  end

  def filter(_actor, _authorizer, _opts) do
    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and
          role in [:owner, :instructor] and gym_id == ^tenant()
      ) or
        (course.status == :published and
           exists(
             Matwork.Gyms.Membership,
             user_id == ^actor(:id) and status == :active and gym_id == ^tenant()
           ))
    )
  end
end
