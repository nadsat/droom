defmodule Droom.UPnP.AVTransport do
  @moduledoc """
  High-level AVTransport control for a `Droom.UPnP.Connection`.

  Every function takes a connection (see `Droom.UPnP.connect/2`).
  Success returns are `:ok`, `{:ok, fields}` or
  `{:error, {:upnp_error, code, description}}`.
  """

  alias Droom.UPnP.Connection

  @type result :: Connection.result()

  @doc "Sets the current track. `metadata` (DIDL-Lite) defaults to empty."
  @spec set_av_transport_uri(GenServer.server(), String.t(), String.t()) :: result()
  def set_av_transport_uri(conn, uri, metadata \\ "") do
    Connection.call(conn, :av, "SetAVTransportURI", %{
      "CurrentURI" => uri,
      "CurrentURIMetaData" => metadata
    })
  end

  @doc ~s|Starts playback. `speed` defaults to `"1"`.|
  @spec play(GenServer.server(), String.t()) :: result()
  def play(conn, speed \\ "1"), do: Connection.call(conn, :av, "Play", %{"Speed" => speed})

  @doc "Pauses playback."
  @spec pause(GenServer.server()) :: result()
  def pause(conn), do: Connection.call(conn, :av, "Pause")

  @doc "Stops playback."
  @spec stop(GenServer.server()) :: result()
  def stop(conn), do: Connection.call(conn, :av, "Stop")

  @doc "Skips to the next track."
  @spec next(GenServer.server()) :: result()
  def next(conn), do: Connection.call(conn, :av, "Next")

  @doc "Skips to the previous track."
  @spec previous(GenServer.server()) :: result()
  def previous(conn), do: Connection.call(conn, :av, "Previous")

  @doc """
  Seeks within the current track. `mode` is one of `"TRACK_NR"`, `"ABS_TIME"`,
  `"REL_TIME"`, `"ABS_COUNT"`, `"REL_COUNT"` or `"CHANNEL_FREQ"`.
  """
  @spec seek(GenServer.server(), String.t(), String.t()) :: result()
  def seek(conn, mode, target) do
    Connection.call(conn, :av, "Seek", %{"Unit" => mode, "Target" => target})
  end

  @doc ~s(Returns transport info, e.g. `%{"CurrentTransportState" => "PLAYING"}`.)
  @spec get_transport_info(GenServer.server()) :: result()
  def get_transport_info(conn), do: Connection.call(conn, :av, "GetTransportInfo")

  @doc ~s|Returns the current transport state (`"STOPPED"`, `"PLAYING"`, ...).|
  @spec get_transport_state(GenServer.server()) :: {:ok, String.t()} | {:error, term()}
  def get_transport_state(conn) do
    case get_transport_info(conn) do
      {:ok, info} -> {:ok, Map.get(info, "CurrentTransportState")}
      other -> other
    end
  end

  @doc "Returns position information for the current track."
  @spec get_position_info(GenServer.server()) :: result()
  def get_position_info(conn), do: Connection.call(conn, :av, "GetPositionInfo")

  @doc "Returns media information for the current track."
  @spec get_media_info(GenServer.server()) :: result()
  def get_media_info(conn), do: Connection.call(conn, :av, "GetMediaInfo")
end
