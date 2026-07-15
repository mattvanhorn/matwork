defmodule Matwork.Gyms.Invite.Changes.GenerateToken do
  @moduledoc "Generates a cryptographically random, URL-safe invite token."
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    token =
      32
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    Ash.Changeset.force_change_attribute(changeset, :token, token)
  end
end
