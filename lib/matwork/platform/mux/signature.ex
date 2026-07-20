defmodule Matwork.Platform.Mux.Signature do
  @moduledoc """
  Verifies a Mux webhook `Mux-Signature` header against the raw request body.
  Header format: `t=<unix_ts>,v1=<hex_hmac_sha256>`; the signed payload is
  `"<t>.<raw_body>"` keyed by the webhook secret. Local crypto only — not a
  Mux API call, so it is not part of the `Platform.Mux` behaviour.
  """

  @spec verify(raw_body :: binary(), header :: String.t() | nil, secret :: String.t()) ::
          :ok | :error
  def verify(raw_body, header, secret)
      when is_binary(raw_body) and is_binary(header) and is_binary(secret) do
    with %{"t" => t, "v1" => provided} <- parse(header),
         expected <- sign(t, raw_body, secret),
         true <- Plug.Crypto.secure_compare(expected, provided) do
      :ok
    else
      _ -> :error
    end
  end

  def verify(_raw_body, _header, _secret), do: :error

  defp parse(header) do
    header
    |> String.split(",")
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Enum.reduce(%{}, fn
      [k, v], acc -> Map.put(acc, String.trim(k), v)
      _, acc -> acc
    end)
  end

  defp sign(t, raw_body, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, "#{t}.#{raw_body}")
    |> Base.encode16(case: :lower)
  end
end
