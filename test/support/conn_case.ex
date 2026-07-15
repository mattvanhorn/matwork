defmodule MatworkWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MatworkWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Plug.Conn

  using do
    quote do
      # The default endpoint for testing
      @endpoint MatworkWeb.Endpoint

      use MatworkWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MatworkWeb.ConnCase
    end
  end

  setup tags do
    Matwork.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Signs `user` into `conn`'s session the same way a real magic-link
  sign-in would, for use in controller and LiveView tests.
  """
  def sign_in(conn, user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    user_with_token = %{user | __metadata__: Map.put(user.__metadata__, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> Helpers.store_in_session(user_with_token)
    |> Conn.assign(:current_user, user)
  end
end
