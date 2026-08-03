defmodule Droom.Test.FakeHEOSResponder do
  @moduledoc """
  A fake SSDP responder for HEOS discovery tests.

  Listens on an ephemeral UDP port, records every datagram it receives (see
  `requests/1`) and answers with a canned HEOS speaker search response
  (`urn:schemas-denon-com:device:ACT-Denon:1`).
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def port(pid), do: GenServer.call(pid, :port)

  def requests(pid), do: GenServer.call(pid, :requests)

  @impl true
  def init(opts) do
    host = Keyword.get(opts, :host, "192.168.1.10")

    with {:ok, socket} <- :gen_udp.open(0, [:binary, {:active, false}, {:reuseaddr, true}]) do
      {:ok, {_addr, port}} = :inet.sockname(socket)
      parent = self()
      spawn_link(fn -> respond_loop(socket, host, parent) end)
      {:ok, %{port: port, requests: []}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}
  def handle_call(:requests, _from, state), do: {:reply, state.requests, state}

  @impl true
  def handle_info({:request, data}, state) do
    {:noreply, %{state | requests: state.requests ++ [data]}}
  end

  defp respond_loop(socket, host, fake) do
    case :gen_udp.recv(socket, 0, :infinity) do
      {:ok, {ip, port, data}} ->
        send(fake, {:request, data})
        :gen_udp.send(socket, ip, port, ssdp_response(host))
        respond_loop(socket, host, fake)

      {:error, _reason} ->
        :ok
    end
  end

  defp ssdp_response(host) do
    "HTTP/1.1 200 OK\r\n" <>
      "CACHE-CONTROL: max-age=1800\r\n" <>
      "LOCATION: http://#{host}:1255/\r\n" <>
      "SERVER: UPnP/1.0\r\n" <>
      "ST: urn:schemas-denon-com:device:ACT-Denon:1\r\n" <>
      "USN: uuid:denon-001::urn:schemas-denon-com:device:ACT-Denon:1\r\n\r\n"
  end
end
