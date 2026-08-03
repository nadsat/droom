defmodule Droom.UPnP.RenderingControl do
  @moduledoc """
  High-level RenderingControl for a `Droom.UPnP.Connection`.

  Every function takes a connection (see `Droom.UPnP.connect/2`).
  Success returns are `:ok`, `{:ok, fields}` or
  `{:error, {:upnp_error, code, description}}`.
  """

  alias Droom.UPnP.Connection

  @type result :: Connection.result()

  @doc ~s(Returns the volume of `channel` as `{:ok, %{"level" => level, "channel" => channel}}`.)
  @spec get_volume(GenServer.server(), String.t()) :: result()
  def get_volume(conn, channel \\ "Master") do
    case Connection.call(conn, :rendering, "GetVolume", %{"Channel" => channel}) do
      {:ok, %{"CurrentVolume" => level}} ->
        {:ok, %{"level" => to_int(level), "channel" => channel}}

      other ->
        other
    end
  end

  @doc "Sets the volume of `channel` (`0`..`100`)."
  @spec set_volume(GenServer.server(), non_neg_integer(), String.t()) :: result()
  def set_volume(conn, level, channel \\ "Master") when is_integer(level) do
    Connection.call(conn, :rendering, "SetVolume", %{
      "Channel" => channel,
      "DesiredVolume" => level
    })
  end

  @doc ~s(Returns the mute state of `channel` as `{:ok, %{"mute" => boolean, "channel" => channel}}`.)
  @spec get_mute(GenServer.server(), String.t()) :: result()
  def get_mute(conn, channel \\ "Master") do
    case Connection.call(conn, :rendering, "GetMute", %{"Channel" => channel}) do
      {:ok, %{"CurrentMute" => mute}} ->
        {:ok, %{"mute" => mute == "1", "channel" => channel}}

      other ->
        other
    end
  end

  @doc "Sets mute on or off for `channel`."
  @spec set_mute(GenServer.server(), boolean(), String.t()) :: result()
  def set_mute(conn, mute, channel \\ "Master") when is_boolean(mute) do
    Connection.call(conn, :rendering, "SetMute", %{
      "Channel" => channel,
      "DesiredMute" => if(mute, do: 1, else: 0)
    })
  end

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp to_int(value), do: value
end
