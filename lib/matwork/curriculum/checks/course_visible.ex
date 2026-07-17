defmodule Matwork.Curriculum.Checks.CourseVisible do
  @moduledoc """
  Filter check for `Course`'s `:read` action. An actor may read a course if:

    * they manage curriculum in this gym (active owner/instructor) — sees all
      courses regardless of status; OR
    * the course is `:published` AND they hold any active membership in this gym.

  Non-members see nothing (in addition to Ash's tenant isolation).
  """
  use Ash.Policy.FilterCheck

  def describe(_opts) do
    "course is published (for active members), or actor manages curriculum in this gym"
  end

  def filter(_actor, _authorizer, _opts) do
    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and
          role in [:owner, :instructor] and gym_id == ^tenant()
      ) or
        (status == :published and
           exists(
             Matwork.Gyms.Membership,
             user_id == ^actor(:id) and status == :active and gym_id == ^tenant()
           ))
    )
  end
end
