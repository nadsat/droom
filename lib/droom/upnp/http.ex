defmodule Droom.UPnP.HTTP do
  @moduledoc false
  # Thin `:httpc` wrappers for fetching device descriptions and posting SOAP
  # actions. Uses plain HTTP; UPnP/DLNA control endpoints are not HTTPS.

  @default_timeout 10_000

  defp http_options(timeout) do
    [{:timeout, timeout}, {:connect_timeout, timeout}]
  end

  @spec get(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get(url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case :httpc.request(:get, {String.to_charlist(url), []}, http_options(timeout), [
           {:body_format, :binary}
         ]) do
      {:ok, {{_version, status, _reason}, _headers, body}} ->
        handle_status(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec post(String.t(), String.t(), binary(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def post(url, soap_action, body, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    headers = [
      {~c"CONTENT-TYPE", ~c"text/xml; charset=\"utf-8\""},
      {~c"SOAPACTION", String.to_charlist(~s("#{soap_action}"))}
    ]

    request = {String.to_charlist(url), headers, ~c"text/xml; charset=\"utf-8\"", body}

    case :httpc.request(:post, request, http_options(timeout), [{:body_format, :binary}]) do
      {:ok, {{_version, status, _reason}, _headers, body}} ->
        handle_status(status, body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_status(status, body) when status in 200..299, do: {:ok, to_binary(body)}
  defp handle_status(status, body), do: {:error, {:http_error, status, to_binary(body)}}

  defp to_binary(body) when is_binary(body), do: body
  defp to_binary(body) when is_list(body), do: List.to_string(body)
end
