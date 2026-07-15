defmodule Matwork.Gyms do
  @moduledoc "The Gyms domain: gym management and tenant roots."
  use Ash.Domain,
    otp_app: :matwork

  resources do
    resource Matwork.Gyms.Gym do
      define :create_gym, action: :create, args: [:name, :slug]
      define :get_gym_by_id, action: :read, get_by: [:id]
      define :get_gym_by_slug, action: :read, get_by: [:slug]
    end

    resource Matwork.Gyms.Membership do
      define :create_owner_membership, action: :create_owner, args: [:user_id]
      define :remove_membership, action: :remove
      define :list_memberships, action: :read
      define :accept_invite, action: :accept_invite, args: [:token]
    end

    resource Matwork.Gyms.Invite do
      define :create_invite, action: :create, args: [:email, :role]
      define :get_invite_by_token, action: :get_by_token, args: [:token]
      define :mark_invite_accepted, action: :mark_accepted
      define :list_invites, action: :read
    end
  end
end
