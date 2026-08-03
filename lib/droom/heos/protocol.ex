defmodule Droom.HEOS.Protocol do
  @moduledoc """
  Pure helpers for the HEOS CLI protocol.

  Commands are `heos://command_group/command?attribute=value&...` strings
  terminated by a newline; responses are JSON documents of the shape

      {"heos": {"command": "...", "result": "success|fail", "message": "..."},
       "payload": ...}

  Attribute values percent-encode `&`, `=` and `%` (`%26`, `%3D`, `%25`); see
  the HEOS CLI Protocol Specification.

  ## Error codes

  A `"fail"` response carries `eid=<code>&text=<description>` in `message`.
  Notable codes: `1` unrecognized command, `2` invalid id, `3` wrong number of
  arguments, `4` data not available, `5` resource not available, `6` invalid
  credentials, `7` command not executed, `8` user not logged in, `9` parameter
  out of range, `10` user not found, `11` internal error, `12` system error
  (with `syserrno`), `13` processing previous command, `14` media can't be
  played, `15` option not supported, `16` too many commands in queue, `17`
  reached skip limit.
  """

  @type params :: %{optional(String.t()) => String.t()}

  @doc """
  Builds a command string for the wire, e.g.

      iex> Droom.HEOS.Protocol.command("player/set_volume", %{"pid" => 1, "level" => 25})
      "heos://player/set_volume?pid=1&level=25"
  """
  @spec command(String.t(), map() | keyword() | nil) :: String.t()
  def command(command, params \\ nil) do
    "heos://" <> command <> query(params)
  end

  @doc """
  Normalizes a decoded response JSON object.

  Returns `{:ok, %{command: path, result: result | nil, message: string | nil,
  payload: term() | nil}}` or `:error` when the object is not a HEOS message.
  """
  @spec parse_message(map()) :: {:ok, map()} | :error
  def parse_message(%{"heos" => %{"command" => command} = heos} = message)
      when is_binary(command) do
    {:ok,
     %{
       command: command,
       result: Map.get(heos, "result"),
       message: Map.get(heos, "message"),
       payload: Map.get(message, "payload")
     }}
  end

  def parse_message(_), do: :error

  @doc """
  Parses a `key=value&key=value` message string into a map, percent-decoding
  each part. Returns an empty map for empty or nil input.
  """
  @spec parse_params(String.t() | nil) :: params()
  def parse_params(nil), do: %{}

  def parse_params(""), do: %{}

  def parse_params(message) when is_binary(message) do
    message
    |> String.split("&", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(acc, URI.decode(key), URI.decode(value))
        [key] -> Map.put(acc, URI.decode(key), "")
      end
    end)
  end

  @doc """
  Extracts the HEOS error from a failed command's `message` string.

  Returns `{:heos_error, eid, text}` where `eid` is `nil` when the message
  carries no error id.
  """
  @spec error_from_message(String.t() | nil) :: {:heos_error, non_neg_integer() | nil, String.t()}
  def error_from_message(message) do
    params = parse_params(message)
    eid = parse_integer(Map.get(params, "eid"))

    text =
      Map.get(params, "text") ||
        case Map.get(params, "syserrno") do
          nil -> message
          syserrno -> "System Error (#{syserrno})"
        end

    {:heos_error, eid, text || ""}
  end

  defp query(nil), do: ""

  defp query(params) when map_size(params) == 0, do: ""

  defp query(params) do
    params
    |> Enum.map_join("&", fn {key, value} -> "#{encode(key)}=#{encode(value)}" end)
    |> then(&("?" <> &1))
  end

  defp encode(value) do
    value
    |> to_string()
    |> String.replace("%", "%25")
    |> String.replace("&", "%26")
    |> String.replace("=", "%3D")
  end

  defp parse_integer(nil), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
