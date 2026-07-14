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
    end
  end
end
