defmodule Droom.UPnP do
  @moduledoc """
  Control UPnP/DLNA media renderers directly via SOAP.

  Devices are located with SSDP discovery (`discover/1`, `start_discovery/1`)
  and controlled through the standard AVTransport and RenderingControl
  services over SOAP/HTTP.

  ## Example

      {:ok, devices} = Droom.UPnP.discover()
      [device | _] = devices
      {:ok, conn} = Droom.UPnP.connect(device)
      Droom.UPnP.AVTransport.set_av_transport_uri(conn, "http://media.example.com/song.mp3")
      Droom.UPnP.AVTransport.play(conn)
      {:ok, %{"level" => volume}} = Droom.UPnP.RenderingControl.get_volume(conn)
  """

  alias Droom.{Device, Discovery, Events}
  alias Droom.UPnP.{Connection, Description, SOAP}

  @media_renderer "urn:schemas-upnp-org:device:MediaRenderer:1"

  @doc """
  Discovers UPnP media renderers (SSDP `MediaRenderer:1`) on the network.

  Pass `:st` in `opts` to search for a different device type (e.g. HEOS
  speakers); see `Droom.Discovery.discover/1`.
  """
  @spec discover(keyword()) :: {:ok, [Device.t()]} | {:error, term()}
  def discover(opts \\ []) do
    Discovery.discover(Keyword.put_new(opts, :st, @media_renderer))
  end

  @doc """
  Starts a continuous discovery process under the `Droom.DiscoverySupervisor`.

  The process listens for SSDP announcements and periodically re-searches for
  `MediaRenderer:1`. Found and lost devices are broadcast on the `:discovery`
  topic; subscribe with `subscribe(:discovery)`.
  """
  @spec start_discovery(keyword()) :: DynamicSupervisor.on_start_child()
  def start_discovery(opts \\ []) do
    DynamicSupervisor.start_child(Droom.DiscoverySupervisor, {Discovery, opts})
  end

  @doc "Subscribes the calling process to events on a topic. See `Droom.Events`."
  @spec subscribe(Events.topic()) :: :ok | {:error, term()}
  def subscribe(topic), do: Phoenix.PubSub.subscribe(Droom.PubSub, Events.topic(topic))

  @doc "Unsubscribes the calling process from a topic."
  @spec unsubscribe(Events.topic()) :: :ok | {:error, term()}
  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(Droom.PubSub, Events.topic(topic))

  @doc """
  Opens a SOAP connection to a UPnP media renderer.

  `target` is a `Droom.Device` (as returned by `discover/1`) or the URL
  of the device description document. The description is fetched and the
  AVTransport and RenderingControl control URLs are extracted.
  """
  @spec connect(Device.t() | String.t(), keyword()) ::
          {:ok, GenServer.server()} | {:error, term()}
  def connect(target, opts \\ [])

  def connect(%Device{location: location}, opts) when is_binary(location) do
    connect(location, opts)
  end

  def connect(location, _opts) when is_binary(location) do
    with {:ok, description} <- Description.fetch(location) do
      urls =
        for service_type <- [SOAP.service_type(:av), SOAP.service_type(:rendering)],
            %{control_url: control_url} = Map.get(description.services, service_type),
            is_binary(control_url) and control_url != "",
            into: %{} do
          {service_type, control_url}
        end

      if map_size(urls) == 0 do
        {:error, :no_control_services}
      else
        start_connection(control_urls: urls, description: description)
      end
    end
  end

  @doc "Closes a SOAP connection."
  @spec close(GenServer.server()) :: :ok
  def close(conn), do: Connection.close(conn)

  defp start_connection(opts) do
    case Process.whereis(Droom.ConnectionSupervisor) do
      nil -> Connection.start_link(opts)
      _ -> DynamicSupervisor.start_child(Droom.ConnectionSupervisor, {Connection, opts})
    end
  end
end
