defmodule Matwork.Curriculum.Validations.VideoInTenant do
  @moduledoc """
  Validates that a Lesson's `video_id` resolves to a `Video` in the same tenant
  (gym_id) as the change. Prevents a curriculum manager in one gym from
  attaching another gym's video by passing an arbitrary video_id.
  """
  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def validate(changeset, _opts, _context) do
    video_id = Ash.Changeset.get_attribute(changeset, :video_id)
    tenant = changeset.tenant

    cond do
      is_nil(video_id) ->
        :ok

      Matwork.Media.Video
      |> Ash.Query.filter(id == ^video_id)
      |> Ash.exists?(tenant: tenant, authorize?: false) ->
        :ok

      true ->
        {:error, field: :video_id, message: "must belong to this gym"}
    end
  end
end
