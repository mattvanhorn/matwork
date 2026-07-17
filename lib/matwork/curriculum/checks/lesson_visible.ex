defmodule Matwork.Curriculum.Checks.LessonVisible do
  @moduledoc """
  Filter check for `Lesson`'s `:read` action: readable if the actor manages
  curriculum in this gym, or the lesson's course is `:published` and the actor
  is any active member. `free_preview` is irrelevant here — it gates playback
  (Session 3), not whether a lesson appears in the tree.
  """
  use Ash.Policy.FilterCheck

  def describe(_opts) do
    "lesson's course is published (for active members), or actor manages curriculum in this gym"
  end

  def filter(_actor, _authorizer, _opts) do
    expr(
      exists(
        Matwork.Gyms.Membership,
        user_id == ^actor(:id) and status == :active and
          role in [:owner, :instructor] and gym_id == ^tenant()
      ) or
        (section.course.status == :published and
           exists(
             Matwork.Gyms.Membership,
             user_id == ^actor(:id) and status == :active and gym_id == ^tenant()
           ))
    )
  end
end
