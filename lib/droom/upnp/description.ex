defmodule Droom.UPnP.Description do
  @moduledoc """
  Fetches and parses a UPnP device description document.

  The description at the SSDP `LOCATION` URL lists the device's services and
  their control URLs, which are needed to send SOAP actions. Relative control
  URLs are resolved against the location URL.
  """

  alias Droom.UPnP.{HTTP, XML}

  @doc """
  Fetches the device description at `location` and returns a map with the
  device's friendly name, model and a `services` map keyed by UPnP service
  type whose values are `%{control_url: url, event_url: url}`.
  """
  @spec fetch(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(location) when is_binary(location) do
    with {:ok, body} <- HTTP.get(location),
         {:ok, description} <- parse(body, location) do
      {:ok, Map.put(description, :location, location)}
    end
  end

  @doc """
  Parses a device description document into the same map shape as `fetch/1`.

  `base_url` (the location of the document) is used to resolve relative
  control URLs; pass `nil` to keep them as-is.
  """
  @spec parse(binary() | charlist(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def parse(body, base_url \\ nil) do
    with {:ok, doc} <- XML.scan(body) do
      case XML.find_by_name(doc, "device") do
        nil ->
          {:error, :not_a_device_description}

        device ->
          {:ok,
           %{
             friendly_name: text(device, "friendlyName"),
             model_name: text(device, "modelName"),
             model_number: text(device, "modelNumber"),
             manufacturer: text(device, "manufacturer"),
             device_type: text(device, "deviceType"),
             services: services(device, base_url)
           }}
      end
    end
  end

  defp services(device, base_url) do
    device
    |> XML.find_by_name("serviceList")
    |> XML.children_by_name("service")
    |> Enum.reduce(%{}, fn service, acc ->
      service_type = text(service, "serviceType")

      if service_type == "" do
        acc
      else
        Map.put(acc, service_type, %{
          control_url: resolve(base_url, text(service, "controlURL")),
          event_url: resolve(base_url, text(service, "eventSubURL"))
        })
      end
    end)
  end

  defp text(container, name) do
    container
    |> XML.find_by_name(name)
    |> XML.text_content()
  end

  defp resolve(_base_url, ""), do: ""
  defp resolve(nil, url), do: url

  defp resolve(base_url, url) do
    case URI.parse(url) do
      %{scheme: scheme} when is_binary(scheme) -> url
      _ -> base_url |> URI.merge(url) |> URI.to_string()
    end
  end
end
