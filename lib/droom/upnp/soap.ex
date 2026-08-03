defmodule Droom.UPnP.SOAP do
  @moduledoc """
  SOAP 1.1 envelope building and response parsing for UPnP services.

  Only the subset used by AVTransport and RenderingControl is implemented:
  request bodies are built as XML and responses are parsed with `:xmerl_sax_parser` into
  maps of action argument names to string values.
  """

  alias Droom.UPnP.XML

  @soap_envelope "http://schemas.xmlsoap.org/soap/envelope/"
  @av_transport "urn:schemas-upnp-org:service:AVTransport:1"
  @rendering_control "urn:schemas-upnp-org:service:RenderingControl:1"

  @type service :: :av | :rendering | String.t()

  @doc "Returns the full UPnP service type for a service alias or passthrough."
  @spec service_type(service()) :: String.t()
  def service_type(:av), do: @av_transport
  def service_type(:rendering), do: @rendering_control
  def service_type(type) when is_binary(type), do: type

  @doc "The value for a `SOAPACTION` header for `action` of `service`."
  @spec soap_action(service(), String.t()) :: String.t()
  def soap_action(service, action), do: "#{service_type(service)}##{action}"

  @doc """
  Builds a SOAP 1.1 request body for `action` of `service`.

  `args` is a map or keyword list of action argument names to values.
  """
  @spec envelope(service(), String.t(), map() | keyword()) :: binary()
  def envelope(service, action, args \\ []) do
    service_type = service_type(service)

    children = Enum.map(args, fn {name, value} -> leaf(to_string(name), to_string(value)) end)

    body =
      element(
        "u:#{action}",
        [~s(xmlns:u="#{service_type}")],
        children
      )

    "<?xml version=\"1.0\"?>" <>
      element("s:Envelope", [~s(xmlns:s="#{@soap_envelope}")], [element("s:Body", [], [body])])
  end

  @doc """
  Parses a SOAP response body.

  Returns `{:ok, fields}` where `fields` maps action argument names (local
  names) to string values, `{:error, {:upnp_error, code, description}}` for a
  `Fault` envelope, or `{:error, reason}` when the body cannot be parsed.
  """
  @spec parse_response(binary() | charlist()) :: {:ok, map()} | {:error, term()}
  def parse_response(body) do
    with {:ok, doc} <- XML.scan(body) do
      case XML.find_by_name(doc, "Body") do
        {_, _, children} ->
          cond do
            fault = XML.find_by_name(children, "Fault") -> fault_result(fault)
            true -> response_result(children)
          end

        nil ->
          {:error, :malformed_response}
      end
    end
  end

  defp element(name, attrs, children) do
    attr_str = Enum.map_join(attrs, " ", & &1)
    prefix = if attr_str == "", do: "", else: " " <> attr_str
    content = IO.iodata_to_binary(children)

    if content == "" do
      "<#{name}#{prefix}/>"
    else
      "<#{name}#{prefix}>#{content}</#{name}>"
    end
  end

  defp leaf(name, value) do
    "<#{name}>#{xml_escape(value)}</#{name}>"
  end

  defp xml_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp fields({_, _, children}) do
    Enum.reduce(children, %{}, fn
      {_, _, _} = element, acc -> Map.put(acc, XML.local_name(element), XML.text_content(element))
      _, acc -> acc
    end)
  end

  defp response_result(children) do
    case Enum.find(children, &match?({_, _, _}, &1)) do
      {_, _, _} = response -> {:ok, fields(response)}
      nil -> {:error, :malformed_response}
    end
  end

  defp fault_result({_, _, _} = fault) do
    case XML.find_by_name(fault, "UPnPError") do
      {_, _, _} = upnp_error ->
        code = XML.find_by_name(upnp_error, "errorCode") |> XML.text_content() |> to_int()
        description = XML.find_by_name(upnp_error, "errorDescription") |> XML.text_content()
        {:error, {:upnp_error, code, description}}

      nil ->
        {:error, :upnp_error}
    end
  end

  defp fault_result(_), do: {:error, :upnp_error}

  defp to_int(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end
end
