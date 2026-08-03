defmodule Droom do
  @moduledoc """
  Top-level entry point for the Droom library.

  Convenience facades over `Droom.Discovery` and `Droom.UPnP` for the
  operations shared by every protocol. Protocol-specific control lives in
  `Droom.UPnP` (SOAP) and `Droom.HEOS` (HEOS CLI).

  ## Example

      {:ok, devices} = Droom.discover()
      Droom.subscribe(:discovery)

      receive do
        {:device_found, device} -> IO.inspect(device)
      end
  """

  alias Droom.{Device, Discovery}

  @doc """
  Runs a one-shot SSDP search and returns the discovered devices.

  See `Droom.Discovery.discover/1` for the available options (`:mx`,
  `:timeout`, `:st`, ...).
  """
  @spec discover(keyword()) :: {:ok, [Device.t()]} | {:error, term()}
  defdelegate discover(opts \\ []), to: Discovery

  @doc "Subscribes the calling process to events on a topic. See `Droom.UPnP.subscribe/1`."
  @spec subscribe(term()) :: :ok | {:error, term()}
  defdelegate subscribe(topic), to: Droom.UPnP

  @doc "Unsubscribes the calling process from a topic. See `Droom.UPnP.unsubscribe/1`."
  @spec unsubscribe(term()) :: :ok | {:error, term()}
  defdelegate unsubscribe(topic), to: Droom.UPnP
end
