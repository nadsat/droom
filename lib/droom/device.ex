defmodule Droom.Device do
  @moduledoc """
  A UPnP device discovered on the network via SSDP.

  Each discovered device exposes a `:host` and `:port`, plus its SSDP
  `LOCATION` URL, which can be passed to `Droom.UPnP.connect/2` to open a
  SOAP control connection.
  """

  @enforce_keys [:usn, :host, :port]
  defstruct [
    :usn,
    :location,
    :st,
    :server,
    :host,
    :port,
    :ttl,
    :last_seen
  ]

  @type t :: %__MODULE__{
          usn: String.t(),
          location: String.t() | nil,
          st: String.t() | nil,
          server: String.t() | nil,
          host: String.t(),
          port: :inet.port_number(),
          ttl: non_neg_integer() | nil,
          last_seen: DateTime.t() | nil
        }

  @doc """
  Builds a `Droom.Device` from a parsed SSDP message.

  The message must be a search response or a `ssdp:alive` notification
  containing at least a `usn` and a `location` header.
  """
  @spec from_ssdp(map()) :: {:ok, t()} | {:error, term()}
  def from_ssdp(%{headers: headers}) do
    with usn when is_binary(usn) <- Map.get(headers, "usn"),
         {:ok, uri} <- parse_location(Map.get(headers, "location")) do
      {:ok,
       %__MODULE__{
         usn: usn,
         location: Map.get(headers, "location"),
         st: Map.get(headers, "st") || Map.get(headers, "nt"),
         server: Map.get(headers, "server"),
         host: uri.host,
         port: uri.port || 80,
         ttl: parse_ttl(Map.get(headers, "cache-control")),
         last_seen: DateTime.utc_now()
       }}
    else
      _ -> {:error, :invalid_ssdp_message}
    end
  end

  @doc """
  Convenience discovery helper: runs a one-shot SSDP search and returns the
  list of devices found within `timeout` milliseconds. See
  `Droom.Discovery.discover/1`.
  """
  @spec discover(keyword()) :: {:ok, [t()]} | {:error, term()}
  def discover(opts \\ []) do
    Droom.Discovery.discover(opts)
  end

  defp parse_location(nil), do: {:error, :missing_location}

  defp parse_location(location) when is_binary(location) do
    uri = URI.parse(location)

    if uri.scheme in ["http", "https"] and uri.host do
      {:ok, uri}
    else
      {:error, :invalid_location}
    end
  end

  defp parse_location(_), do: {:error, :invalid_location}

  defp parse_ttl(nil), do: nil

  defp parse_ttl(cache_control) do
    case Regex.run(~r/max-age=(\d+)/i, cache_control, capture: :all_but_first) do
      [max_age] -> String.to_integer(max_age)
      _ -> nil
    end
  end
end
