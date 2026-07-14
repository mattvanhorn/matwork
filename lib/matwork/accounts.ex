defmodule Matwork.Accounts do
  @moduledoc "Ash domain for User identity and authentication."
  use Ash.Domain,
    otp_app: :matwork

  resources do
    resource Matwork.Accounts.Token
    resource Matwork.Accounts.User
  end
end
