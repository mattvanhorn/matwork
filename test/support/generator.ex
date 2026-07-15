defmodule Matwork.Generator do
  @moduledoc false
  use Ash.Generator

  alias Matwork.Accounts.User
  alias Matwork.Gyms.Gym
  alias Matwork.Gyms.Membership

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

  def membership(opts \\ []) do
    {owning_gym, opts} = Keyword.pop(opts, :gym)
    {as_user, opts} = Keyword.pop(opts, :user)
    {role, opts} = Keyword.pop(opts, :role, :student)
    {status, opts} = Keyword.pop(opts, :status, :active)

    owning_gym = owning_gym || generate(gym())
    as_user = as_user || generate(user())

    seed_generator(
      %Membership{
        gym_id: owning_gym.id,
        user_id: as_user.id,
        role: role,
        status: status
      },
      overrides: opts
    )
  end

  def invite(opts \\ []) do
    {owning_gym, opts} = Keyword.pop(opts, :gym)
    {inviter, opts} = Keyword.pop(opts, :inviter)

    owning_gym = owning_gym || generate(gym())
    inviter = inviter || owning_gym.owner_id |> then(&%Matwork.Accounts.User{id: &1})

    changeset_generator(
      Matwork.Gyms.Invite,
      :create,
      defaults: [
        email: sequence(:invite_email, &"student-#{&1}@example.com"),
        role: :student
      ],
      actor: inviter,
      tenant: owning_gym.id,
      overrides: opts
    )
  end
end
