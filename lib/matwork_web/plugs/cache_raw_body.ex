defmodule MatworkWeb.Plugs.CacheRawBody do
  @moduledoc """
  Custom `Plug.Parsers` body reader that stashes the raw request body on the
  conn for webhook paths, so a controller can verify an HMAC signature over the
  exact bytes the provider signed. Scoped to `/webhooks/` to avoid retaining
  every request body in memory.
  """
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache(conn, body)}
      {:more, body, conn} -> {:more, body, cache(conn, body)}
      other -> other
    end
  end

  defp cache(%Plug.Conn{request_path: "/webhooks/" <> _} = conn, body) do
    update_in(conn.assigns[:raw_body], fn
      nil -> [body]
      chunks -> [body | chunks]
    end)
  end

  defp cache(conn, _body), do: conn

  @doc "Returns the accumulated raw body (or nil) as a single binary."
  def raw_body(%Plug.Conn{assigns: %{raw_body: chunks}}) when is_list(chunks) do
    chunks |> Enum.reverse() |> IO.iodata_to_binary()
  end

  def raw_body(_conn), do: nil
end
