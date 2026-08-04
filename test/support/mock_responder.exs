defmodule Droom.Test.MockResponder do
  @moduledoc """
  A fake SSDP responder used to test discovery.

  Listens on an ephemeral UDP port and answers every datagram it receives
  with a canned UPnP media renderer SSDP search response.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def port(pid), do: GenServer.call(pid, :port)

  @impl true
  def init(opts) do
    host = Keyword.get(opts, :host, "192.168.1.10")

    with {:ok, socket} <- :gen_udp.open(0, [:binary, {:active, false}, {:reuseaddr, true}]) do
      {:ok, {_addr, port}} = :inet.sockname(socket)
      spawn_link(fn -> respond_loop(socket, host) end)
      {:ok, %{port: port}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  defp respond_loop(socket, host) do
    case :gen_udp.recv(socket, 0, :infinity) do
      {:ok, {ip, port, _data}} ->
        :gen_udp.send(socket, ip, port, ssdp_response(host))
        respond_loop(socket, host)

      {:error, _reason} ->
        :ok
    end
  end

  defp ssdp_response(host) do
    "HTTP/1.1 200 OK\r\n" <>
      "CACHE-CONTROL: max-age=1800\r\n" <>
      "LOCATION: http://#{host}:8080/upnp/desc/device_description.xml\r\n" <>
      "SERVER: UPnP/1.0\r\n" <>
      "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" <>
      "USN: uuid:123-456::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
  end
end
