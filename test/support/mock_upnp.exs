defmodule Droom.Test.MockUPnP do
  @moduledoc """
  An in-memory fake UPnP media renderer for tests.

  Listens on an ephemeral HTTP port, serves a device description on
  `/description.xml` and answers SOAP actions on `/control/AVTransport` and
  `/control/RenderingControl`. Records every HTTP request (see `requests/1`)
  and can be configured to fail specific actions with
  `fail: ["SetVolume"]`.
  """

  use GenServer

  @control_ns_av "urn:schemas-upnp-org:service:AVTransport:1"
  @control_ns_rendering "urn:schemas-upnp-org:service:RenderingControl:1"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "The port the fake renderer is listening on."
  def port(pid), do: GenServer.call(pid, :port)

  @doc "The URL of the device description."
  def description_url(pid), do: "http://127.0.0.1:#{port(pid)}/description.xml"

  @doc "The list of HTTP requests received so far."
  def requests(pid), do: GenServer.call(pid, :requests)

  @impl true
  def init(opts) do
    fail = Keyword.get(opts, :fail, [])

    listen_opts = [:binary, {:packet, :raw}, {:active, false}, {:reuseaddr, true}]

    with {:ok, listen_socket} <- :gen_tcp.listen(0, listen_opts) do
      {:ok, {_addr, port}} = :inet.sockname(listen_socket)
      parent = self()
      spawn_link(fn -> accept_loop(listen_socket, parent, fail) end)
      {:ok, %{port: port, requests: [], fail: fail}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}
  def handle_call(:requests, _from, state), do: {:reply, state.requests, state}

  @impl true
  def handle_info({:request, request}, state) do
    {:noreply, %{state | requests: state.requests ++ [request]}}
  end

  defp accept_loop(listen_socket, fake, fail) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        handler = spawn_link(fn -> handler(socket, fake, fail) end)
        :gen_tcp.controlling_process(socket, handler)
        accept_loop(listen_socket, fake, fail)

      {:error, _reason} ->
        :ok
    end
  end

  defp handler(socket, fake, fail) do
    case read_request(socket) do
      {:ok, request} ->
        send(fake, {:request, request})
        {status, body} = respond(request, fail)
        :gen_tcp.send(socket, response(status, body))
        :gen_tcp.close(socket)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp read_request(socket) do
    with {:ok, head, rest} <- recv_head(socket, ""),
         {method, path, headers} <- parse_head(head),
         {:ok, body} <- read_body(socket, rest, content_length(headers)) do
      {:ok, %{method: method, path: path, headers: headers, body: body}}
    end
  end

  defp recv_head(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        {:ok, head, rest}

      [_] ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, data} -> recv_head(socket, buffer <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp read_body(_socket, buffer, length) when byte_size(buffer) >= length do
    {:ok, binary_part(buffer, 0, length)}
  end

  defp read_body(socket, buffer, length) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} -> read_body(socket, buffer <> data, length)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_head(head) do
    [request_line | lines] = String.split(head, "\r\n")
    [method, path | _] = String.split(request_line, " ")
    headers = parse_headers(lines)
    {method, path, headers}
  end

  defp parse_headers(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put(acc, String.downcase(key), String.trim(value))
        [_] -> acc
      end
    end)
  end

  defp content_length(headers) do
    case Map.get(headers, "content-length") do
      nil -> 0
      length -> String.to_integer(length)
    end
  end

  defp respond(%{method: "GET", path: "/description.xml"}, _fail) do
    {200, description_xml()}
  end

  defp respond(%{method: "POST", headers: headers}, fail) do
    case Map.get(headers, "soapaction") do
      nil ->
        {400, ""}

      soapaction ->
        action = soapaction |> String.trim("\"") |> String.split("#") |> List.last()
        soap_response(action, fail)
    end
  end

  defp respond(_request, _fail), do: {404, ""}

  defp soap_response(action, fail) do
    if action in fail do
      {500, error_xml("701", "Invalid Action")}
    else
      {200, ok_xml(action)}
    end
  end

  defp ok_xml(action) do
    service_ns =
      if action in ~w(GetVolume SetVolume GetMute SetMute),
        do: @control_ns_rendering,
        else: @control_ns_av

    body =
      case action do
        "GetTransportInfo" ->
          "<CurrentTransportState>PLAYING</CurrentTransportState>" <>
            "<CurrentTransportStatus>OK</CurrentTransportStatus>" <>
            "<CurrentSpeed>1</CurrentSpeed>"

        "GetPositionInfo" ->
          "<Track>1</Track>" <>
            "<TrackDuration>00:03:20</TrackDuration>" <>
            "<TrackMetaData></TrackMetaData>" <>
            "<TrackURI>http://example.com/song.mp3</TrackURI>" <>
            "<RelTime>00:00:42</RelTime>"

        "GetMediaInfo" ->
          "<CurrentURI>http://example.com/song.mp3</CurrentURI>" <>
            "<CurrentURIMetaData></CurrentURIMetaData>"

        "GetVolume" ->
          "<CurrentVolume>30</CurrentVolume>"

        "GetMute" ->
          "<CurrentMute>0</CurrentMute>"

        _ ->
          ""
      end

    ~s|<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:#{action}Response xmlns:u="#{service_ns}">#{body}</u:#{action}Response></s:Body></s:Envelope>|
  end

  defp error_xml(code, description) do
    ~s|<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>#{code}</errorCode><errorDescription>#{description}</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>|
  end

  defp description_xml do
    ~s|<?xml version="1.0" encoding="utf-8"?><root xmlns="urn:schemas-upnp-org:device-1-0"><specVersion><major>1</major><minor>0</minor></specVersion><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType><friendlyName>Test Renderer</friendlyName><manufacturer>Droom</manufacturer><modelName>TestModel</modelName><modelNumber>1</modelNumber><UDN>uuid:test-renderer</UDN><serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><serviceId>urn:upnp-org:serviceId:AVTransport</serviceId><controlURL>/control/AVTransport</controlURL><eventSubURL>/control/AVTransport/Event</eventSubURL><SCPDURL>/SCPD/AVTransport.xml</SCPDURL></service><service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId><controlURL>/control/RenderingControl</controlURL><eventSubURL>/control/RenderingControl/Event</eventSubURL><SCPDURL>/SCPD/RenderingControl.xml</SCPDURL></service></serviceList></device></root>|
  end

  defp response(status, body) do
    "HTTP/1.1 #{status} #{reason_phrase(status)}\r\n" <>
      "CONTENT-TYPE: text/xml; charset=\"utf-8\"\r\n" <>
      "CONTENT-LENGTH: #{byte_size(body)}\r\n" <>
      "CONNECTION: close\r\n\r\n" <>
      body
  end

  defp reason_phrase(200), do: "OK"
  defp reason_phrase(400), do: "Bad Request"
  defp reason_phrase(404), do: "Not Found"
  defp reason_phrase(500), do: "Internal Server Error"
  defp reason_phrase(_), do: ""
end
