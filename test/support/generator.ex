defmodule Matwork.Generator do
  @moduledoc false
  use Ash.Generator

  alias Matwork.Accounts.User
  alias Matwork.Gyms.Gym

  def user(opts \\ []) do
    seed_generator(
      %User{
        email: sequence(:user_email, &"user-#{&1}@example.com")
      },
      overrides: opts
    )
  end

  def gym(opts \\ []) do
    {owner, opts} = Keyword.pop(opts, :owner)
    owner = owner || generate(user())

    changeset_generator(
      Gym,
      :create,
      defaults: [
        name: sequence(:gym_name, &"Gym #{&1}"),
        slug: sequence(:gym_slug, &"gym-#{&1}")
      ],
      actor: owner,
      overrides: opts
    )
  end
end
