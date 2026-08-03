defmodule Droom.SSDP do
  @moduledoc """
  Minimal SSDP (UPnP Simple Service Discovery Protocol) support.

  Provides building of `M-SEARCH` discovery requests and parsing of SSDP
  messages received over UDP. Discovery is used to locate UPnP media renderers
  on the network; actual control happens over SOAP (see `Droom.UPnP`).
  """

  @multicast_group {239, 255, 255, 250}
  @multicast_port 1900
  @search_target "urn:schemas-upnp-org:device:MediaRenderer:1"

  @type t :: %{kind: :response | :notify, status: pos_integer() | nil, headers: map()}

  @doc "The SSDP multicast group used for discovery."
  @spec multicast_group() :: tuple()
  def multicast_group, do: @multicast_group

  @doc "The SSDP multicast port used for discovery."
  @spec multicast_port() :: :inet.port_number()
  def multicast_port, do: @multicast_port

  @doc "The default UPnP search target (`MediaRenderer:1`)."
  @spec search_target() :: String.t()
  def search_target, do: @search_target

  @doc """
  Builds an `M-SEARCH` discovery request.

  `mx` is the discovery response window in seconds.
  """
  @spec msearch(String.t(), pos_integer()) :: binary()
  def msearch(target \\ @search_target, mx \\ 3) do
    "M-SEARCH * HTTP/1.1\r\n" <>
      "HOST: #{format_endpoint(@multicast_group, @multicast_port)}\r\n" <>
      "MAN: \"ssdp:discover\"\r\n" <>
      "MX: #{mx}\r\n" <>
      "ST: #{target}\r\n\r\n"
  end

  @doc """
  Parses a raw SSDP UDP datagram into a `Droom.SSDP.t()`.

  Header names are lower-cased in the returned map.
  """
  @spec parse(binary()) :: t()
  def parse(packet) when is_binary(packet) do
    [start_line | lines] = :binary.split(packet, "\r\n", [:global])

    case start_line do
      "NOTIFY * HTTP/1.1" ->
        %{kind: :notify, status: nil, headers: parse_headers(lines)}

      "HTTP/1.1 200 OK" ->
        %{kind: :response, status: 200, headers: parse_headers(lines)}

      _other ->
        %{kind: :response, status: nil, headers: parse_headers(lines)}
    end
  end

  @doc "Checks whether a parsed message is a `ssdp:byebye` notification."
  @spec byebye?(t()) :: boolean()
  def byebye?(%{kind: :notify, headers: headers}) do
    nts = headers["nts"]
    nts == "ssdp:byebye" or nts == "ssdp:update"
  end

  def byebye?(_), do: false

  @doc "Checks whether a parsed message is a `ssdp:alive` notification or a search response."
  @spec alive?(t()) :: boolean()
  def alive?(%{kind: :notify, headers: headers}) do
    headers["nts"] in ["ssdp:alive", nil]
  end

  def alive?(%{kind: :response}), do: true
  def alive?(_), do: false

  defp parse_headers(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case :binary.split(line, ":", [:global]) do
        [_] ->
          acc

        [key | rest] ->
          value = rest |> Enum.join(":") |> String.trim()
          Map.put(acc, String.downcase(String.trim(key)), value)
      end
    end)
  end

  defp format_endpoint(ip, port) do
    "#{ip |> Tuple.to_list() |> Enum.join(".")}:#{port}"
  end
end
