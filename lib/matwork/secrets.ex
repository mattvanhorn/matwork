defmodule Matwork.Secrets do
  @moduledoc "Resolves signing secrets for AshAuthentication at runtime."
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Matwork.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:matwork, :token_signing_secret)
  end
end
