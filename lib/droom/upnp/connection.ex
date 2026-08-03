defmodule Droom.UPnP.Connection do
  @moduledoc """
  A SOAP connection to a single UPnP media renderer.

  There is no persistent socket: every action is a stateless SOAP/HTTP `POST`
  to the device's control URL. The process holds the control URLs extracted
  from the device description and serializes actions through `call/5`.

  Connections are normally started via `Droom.UPnP.connect/2`.
  """

  use GenServer, restart: :temporary

  alias Droom.UPnP.{HTTP, SOAP}

  @instance_id "0"

  defstruct [:control_urls, :description]

  @type result ::
          :ok
          | {:ok, map()}
          | {:error, {:upnp_error, term(), String.t() | nil}}
          | {:error, term()}

  @doc "Starts a connection process. `:control_urls` is required."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @doc """
  Calls a SOAP action on the connection's device.

  `service` is `:av`, `:rendering` or a full UPnP service type; `args` are the
  action's named arguments. An `InstanceID` of `0` is added automatically.

  Returns `:ok` for actions without response arguments and `{:ok, fields}`
  for queries, where `fields` maps argument names to string values.
  """
  @spec call(GenServer.server(), SOAP.service(), String.t(), map() | keyword(), keyword()) ::
          result()
  def call(server, service, action, args \\ [], opts \\ []) do
    GenServer.call(server, {:call, service, action, args, opts}, :infinity)
  end

  @doc "Returns the device description the connection was built from."
  @spec description(GenServer.server()) :: map() | nil
  def description(server), do: GenServer.call(server, :description)

  @doc "Closes the connection."
  @spec close(GenServer.server()) :: :ok
  def close(server), do: GenServer.stop(server, :normal)

  @impl true
  def init(opts) do
    control_urls = Keyword.fetch!(opts, :control_urls)

    {:ok, %__MODULE__{control_urls: control_urls, description: Keyword.get(opts, :description)}}
  end

  @impl true
  def handle_call({:call, service, action, args, opts}, _from, state) do
    service_type = SOAP.service_type(service)
    url = Map.get(state.control_urls, service_type)

    result =
      case url do
        nil -> {:error, {:no_control_url, service_type}}
        _ -> perform(url, service_type, action, args, opts)
      end

    {:reply, result, state}
  end

  def handle_call(:description, _from, state), do: {:reply, state.description, state}

  defp perform(url, service_type, action, args, opts) do
    args = Map.merge(%{"InstanceID" => @instance_id}, Map.new(args))
    body = SOAP.envelope(service_type, action, args)
    soap_action = SOAP.soap_action(service_type, action)

    case HTTP.post(url, soap_action, body, opts) do
      {:ok, response_body} ->
        normalize(SOAP.parse_response(response_body))

      {:error, {:http_error, 500, response_body}} ->
        # A SOAP Fault is delivered as an HTTP 500 with the error in the body.
        case SOAP.parse_response(response_body) do
          {:error, _} = error -> error
          {:ok, _} -> {:error, :upnp_error}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp normalize({:ok, %{} = fields}) when map_size(fields) == 0, do: :ok
  defp normalize(other), do: other
end
