defmodule Matwork.Accounts do
  use Ash.Domain,
    otp_app: :matwork

  resources do
    resource Matwork.Accounts.Token
    resource Matwork.Accounts.User
  end
end
