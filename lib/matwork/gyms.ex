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
  end
end
