defmodule Droom.Discovery do
  @moduledoc """
  Discovers UPnP devices on the local network using SSDP.

  Two entry points are provided:

    * `discover/1` — a one-shot blocking search that returns the devices
      currently visible on the network.
    * `Droom.Discovery` — a `GenServer` that keeps listening for SSDP
      `NOTIFY` announcements (alive/byebye) and periodically re-sends
      `M-SEARCH`. Found/lost devices are broadcast on the
      `droom:discovery` topic (see `Droom.UPnP.subscribe/1`).
  """

  use GenServer
  require Logger

  alias Droom.{Device, Events, SSDP}

  @default_interval 30_000

  defstruct [
    :socket,
    :target_ip,
    :target_port,
    :mx,
    :st,
    :interval,
    devices: %{},
    timer: nil
  ]

  @type t :: %__MODULE__{}

  @doc """
  Runs a one-shot SSDP search and returns the discovered devices.

  Options:

    * `:mx` — SSDP response window in seconds (default `3`)
    * `:timeout` — how long to wait for responses in milliseconds
      (default `(mx + 1) * 1000`)
    * `:target_ip` / `:target_port` — where to send the `M-SEARCH`
      (defaults to the SSDP multicast group)
    * `:source_port` — local port to bind (defaults to the SSDP port `1900`)
    * `:st` — the search target (defaults to `MediaRenderer:1`)
  """
  @spec discover(keyword()) :: {:ok, [Device.t()]} | {:error, term()}
  def discover(opts \\ []) do
    mx = Keyword.get(opts, :mx, 3)
    timeout = Keyword.get(opts, :timeout, (mx + 1) * 1000)
    st = Keyword.get(opts, :st, SSDP.search_target())
    {target_ip, target_port} = target(opts)

    with {:ok, sock} <- open_socket(Keyword.put(opts, :active, false)) do
      try do
        send_msearch(sock, target_ip, target_port, mx, st)
        deadline = System.monotonic_time(:millisecond) + timeout

        devices =
          sock
          |> collect_until(deadline, %{})
          |> Map.values()
          |> Enum.sort_by(& &1.host)

        {:ok, devices}
      after
        :gen_udp.close(sock)
      end
    end
  end

  @doc "Starts a continuously-listening discovery process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Returns the devices currently known to a discovery process."
  @spec devices(GenServer.server()) :: [Device.t()]
  def devices(server \\ __MODULE__), do: GenServer.call(server, :devices)

  @doc "Returns the local port the discovery process bound its socket to."
  @spec local_port(GenServer.server()) :: :inet.port_number()
  def local_port(server \\ __MODULE__), do: GenServer.call(server, :local_port)

  @doc "Sends an immediate `M-SEARCH` from a discovery process."
  @spec search(GenServer.server()) :: :ok
  def search(server \\ __MODULE__), do: GenServer.call(server, :search)

  @impl true
  def init(opts) do
    mx = Keyword.get(opts, :mx, 3)
    interval = Keyword.get(opts, :interval, @default_interval)
    st = Keyword.get(opts, :st, SSDP.search_target())
    {target_ip, target_port} = target(opts)

    case open_socket(Keyword.put(opts, :active, true)) do
      {:ok, sock} ->
        state = %__MODULE__{
          socket: sock,
          target_ip: target_ip,
          target_port: target_port,
          mx: mx,
          st: st,
          interval: interval
        }

        {:ok, state, {:continue, :search}}

      {:error, reason} ->
        Logger.error("Droom.Discovery: could not open SSDP socket |#{inspect(reason)}|")
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:search, state), do: {:noreply, run_search(state)}

  @impl true
  def handle_call(:devices, _from, state) do
    {:reply, Map.values(state.devices), state}
  end

  def handle_call(:search, _from, state) do
    {:reply, :ok, run_search(state)}
  end

  def handle_call(:local_port, _from, state) do
    {:ok, {_addr, port}} = :inet.sockname(state.socket)
    {:reply, port, state}
  end

  @impl true
  def handle_info(:search, state), do: {:noreply, run_search(state)}

  def handle_info({:udp, _sock, _ip, _port, data}, state) do
    {:noreply, process_packet(state, data)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  defp run_search(%__MODULE__{} = state) do
    send_msearch(state.socket, state.target_ip, state.target_port, state.mx, state.st)

    timer = Process.send_after(self(), :search, state.interval)
    %__MODULE__{state | timer: timer}
  end

  defp process_packet(state, data) do
    msg = SSDP.parse(data)

    cond do
      SSDP.byebye?(msg) -> handle_byebye(state, msg)
      SSDP.alive?(msg) -> handle_alive(state, msg)
      true -> state
    end
  end

  defp handle_alive(%__MODULE__{} = state, msg) do
    case Device.from_ssdp(msg) do
      {:ok, device} ->
        devices = Map.put(state.devices, device.usn, device)

        if device.usn in Map.keys(state.devices) do
          %__MODULE__{state | devices: devices}
        else
          Events.broadcast(:discovery, {:device_found, device})
          %__MODULE__{state | devices: devices}
        end

      {:error, _reason} ->
        state
    end
  end

  defp handle_byebye(%__MODULE__{} = state, msg) do
    usn = get_in(msg.headers, ["usn"])

    if usn && Map.has_key?(state.devices, usn) do
      device = state.devices[usn]
      Events.broadcast(:discovery, {:device_lost, usn, device})
      %__MODULE__{state | devices: Map.delete(state.devices, usn)}
    else
      state
    end
  end

  defp collect_until(sock, deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      acc
    else
      case :gen_udp.recv(sock, 0, remaining) do
        {:ok, {_ip, _port, data}} ->
          acc = add_device(SSDP.parse(data), acc)
          collect_until(sock, deadline, acc)

        {:error, :timeout} ->
          acc
      end
    end
  end

  defp add_device(msg, acc) do
    with true <- SSDP.alive?(msg),
         {:ok, device} <- Device.from_ssdp(msg) do
      Map.put(acc, device.usn, device)
    else
      _ -> acc
    end
  end

  defp open_socket(opts) do
    active = Keyword.get(opts, :active, false)
    source_port = Keyword.get(opts, :source_port, SSDP.multicast_port())

    base_opts = [
      :binary,
      {:active, active},
      {:reuseaddr, true},
      {:multicast_ttl, 4},
      {:multicast_loop, true}
    ]

    membership = {:add_membership, {SSDP.multicast_group(), :any}}

    case :gen_udp.open(source_port, [membership | base_opts]) do
      {:ok, sock} ->
        {:ok, sock}

      {:error, :eaddrinuse} ->
        # Port 1900 is held by another listener (e.g. a media player). Fall
        # back to an ephemeral source port; unicast replies to our M-SEARCH
        # will still be delivered, but multicast NOTIFYs will not.
        :gen_udp.open(0, base_opts)

      {:error, _reason} ->
        # Multicast may be unavailable in this environment; retry without it.
        :gen_udp.open(source_port, base_opts)
    end
  end

  defp send_msearch(sock, target_ip, target_port, mx, st) do
    :gen_udp.send(sock, target_ip, target_port, SSDP.msearch(st, mx))
  end

  defp target(opts) do
    ip =
      opts
      |> Keyword.get(:target_ip, SSDP.multicast_group())
      |> normalize_ip()

    port = Keyword.get(opts, :target_port, SSDP.multicast_port())
    {ip, port}
  end

  defp normalize_ip(ip) when is_tuple(ip), do: ip

  defp normalize_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, tuple} -> tuple
      _ -> SSDP.multicast_group()
    end
  end

  defp normalize_ip(_), do: SSDP.multicast_group()
end
