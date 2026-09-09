defmodule Droom.HEOS do
  @moduledoc """
  Control Denon HEOS speakers over the HEOS CLI protocol.

  The HEOS CLI is a newline-terminated TCP protocol on port `1255`. A single
  connection to any speaker in the system exposes every player, group, queue
  and online service on the network, so one connection is enough to control a
  whole multi-room setup. There is no authentication.

  Speakers are located with SSDP discovery (`discover/1`, search target
  `urn:schemas-denon-com:device:ACT-Denon:1`) and controlled with `call/3` or
  the command helpers below.

  ## Example

      {:ok, [device | _]} = Droom.HEOS.discover()
      {:ok, conn} = Droom.HEOS.connect(device)
      {:ok, [player | _]} = Droom.HEOS.get_players(conn)

      Droom.HEOS.play(conn, player["pid"])
      {:ok, %{"level" => level}} = Droom.HEOS.get_volume(conn, player["pid"])
  """

  alias Droom.HEOS.Connection
  alias Droom.Device

  @port 1255
  @search_target "urn:schemas-denon-com:device:ACT-Denon:1"

  @type result :: Connection.result()

  @doc """
  Discovers HEOS speakers via SSDP. See `Droom.UPnP.discover/1` for the
  available options (`:mx`, `:timeout`, ...).
  """
  @spec discover(keyword()) :: {:ok, [Device.t()]} | {:error, term()}
  def discover(opts \\ []) do
    Droom.UPnP.discover(Keyword.put(opts, :st, @search_target))
  end

  @doc """
  Opens a HEOS CLI connection to a speaker.

  `target` is a `Droom.Device` (as returned by `discover/1`) or the host
  (IP address or hostname) of any speaker in the system. Options include
  `:port` (default `1255`) and `:connect_timeout` (milliseconds).
  """
  @spec connect(Device.t() | String.t(), keyword()) ::
          {:ok, GenServer.server()} | {:error, term()}
  def connect(target, opts \\ [])

  def connect(%Device{host: host}, opts) when is_binary(host) do
    connect(host, opts)
  end

  def connect(%Device{}, _opts), do: {:error, :missing_host}

  def connect(host, opts) when is_binary(host) do
    start_connection(Keyword.put_new(opts, :host, host) |> Keyword.put_new(:port, @port))
  end

  def connect(_target, _opts), do: {:error, :invalid_target}

  @doc "Closes a HEOS connection."
  @spec close(GenServer.server()) :: :ok
  def close(conn), do: Connection.close(conn)

  @doc "Re-establishes a dropped HEOS connection."
  @spec reconnect(GenServer.server()) :: :ok | {:error, term()}
  def reconnect(conn), do: Connection.reconnect(conn)

  @doc """
  Sends a CLI command and waits for its response.

  `command` is a `command_group/command` path and `params` its attributes,
  e.g. `call(conn, "player/set_volume", %{"pid" => 1, "level" => 25})`. See
  `Droom.HEOS.Connection.call/4` for the return values.
  """
  @spec call(GenServer.server(), String.t(), map() | keyword() | nil) :: result()
  def call(conn, command, params \\ nil), do: Connection.call(conn, command, params)

  @doc "Subscribes the calling process to HEOS events (see `Droom.Events`)."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Droom.UPnP.subscribe(:heos)

  @doc "Unsubscribes the calling process from HEOS events."
  @spec unsubscribe() :: :ok | {:error, term()}
  def unsubscribe, do: Droom.UPnP.unsubscribe(:heos)

  @doc "Asks the speaker to confirm the connection is still alive."
  @spec heart_beat(GenServer.server()) :: result()
  def heart_beat(conn), do: call(conn, "system/heart_beat")

  @doc "Starts receiving change events from the speaker."
  @spec register_for_change_events(GenServer.server()) :: result()
  def register_for_change_events(conn), do: call(conn, "system/register_for_change_events")

  @doc "Returns all players in the system."
  @spec get_players(GenServer.server()) :: result()
  def get_players(conn), do: call(conn, "player/get_players")

  @doc "Returns information about one player."
  @spec get_player_info(GenServer.server(), term()) :: result()
  def get_player_info(conn, pid), do: call(conn, "player/get_player_info", %{"pid" => pid})

  @doc "Returns the play state of a player (`play`, `pause` or `stop`)."
  @spec get_play_state(GenServer.server(), term()) :: result()
  def get_play_state(conn, pid), do: call(conn, "player/get_play_state", %{"pid" => pid})

  @doc "Sets the play state of a player (`play`, `pause` or `stop`)."
  @spec set_play_state(GenServer.server(), term(), String.t()) :: result()
  def set_play_state(conn, pid, state),
    do: call(conn, "player/set_play_state", %{"pid" => pid, "state" => state})

  @doc "Starts playback on a player."
  @spec play(GenServer.server(), term()) :: result()
  def play(conn, pid), do: set_play_state(conn, pid, "play")

  @doc "Pauses playback on a player."
  @spec pause(GenServer.server(), term()) :: result()
  def pause(conn, pid), do: set_play_state(conn, pid, "pause")

  @doc "Stops playback on a player."
  @spec stop(GenServer.server(), term()) :: result()
  def stop(conn, pid), do: set_play_state(conn, pid, "stop")

  @doc "Toggles between play and pause on a player."
  @spec toggle_play_pause(GenServer.server(), term()) :: result()
  def toggle_play_pause(conn, pid), do: call(conn, "player/toggle_play_pause", %{"pid" => pid})

  @doc "Returns the current volume of a player (`0`..`100`)."
  @spec get_volume(GenServer.server(), term()) :: result()
  def get_volume(conn, pid), do: call(conn, "player/get_volume", %{"pid" => pid})

  @doc "Sets the volume of a player (`0`..`100`)."
  @spec set_volume(GenServer.server(), term(), non_neg_integer()) :: result()
  def set_volume(conn, pid, level) when is_integer(level) do
    call(conn, "player/set_volume", %{"pid" => pid, "level" => level})
  end

  @doc "Raises the volume of a player by one step."
  @spec volume_up(GenServer.server(), term()) :: result()
  def volume_up(conn, pid), do: call(conn, "player/volume_up", %{"pid" => pid})

  @doc "Lowers the volume of a player by one step."
  @spec volume_down(GenServer.server(), term()) :: result()
  def volume_down(conn, pid), do: call(conn, "player/volume_down", %{"pid" => pid})

  @doc "Returns the mute state of a player (`on` or `off`)."
  @spec get_mute(GenServer.server(), term()) :: result()
  def get_mute(conn, pid), do: call(conn, "player/get_mute", %{"pid" => pid})

  @doc "Sets the mute state of a player (`on` or `off`)."
  @spec set_mute(GenServer.server(), term(), String.t()) :: result()
  def set_mute(conn, pid, state) when state in ["on", "off"] do
    call(conn, "player/set_mute", %{"pid" => pid, "state" => state})
  end

  @doc "Returns the media currently playing on a player."
  @spec get_now_playing_media(GenServer.server(), term()) :: result()
  def get_now_playing_media(conn, pid),
    do: call(conn, "player/get_now_playing_media", %{"pid" => pid})

  @doc "Returns the queue of a player."
  @spec get_queue(GenServer.server(), term()) :: result()
  def get_queue(conn, pid), do: call(conn, "player/get_queue", %{"pid" => pid})

  @doc "Plays the queue with id `qid` on a player."
  @spec play_queue(GenServer.server(), term(), term()) :: result()
  def play_queue(conn, pid, qid),
    do: call(conn, "player/play_queue", %{"pid" => pid, "qid" => qid})

  @doc "Returns all groups in the system."
  @spec get_groups(GenServer.server()) :: result()
  def get_groups(conn), do: call(conn, "group/get_groups")

  @doc "Returns music sources."
  @spec get_music_sources(GenServer.server()) :: result()
  def get_music_sources(conn), do: call(conn, "browse/get_music_sources")

  @doc "Returns music_source by id."
  @spec get_music_source(GenServer.server(), Integer.t()) :: result()
  def get_music_source(conn, service_id),
    do: call(conn, "browse/browse", %{"sid" => service_id})

  @doc "Returns container info."
  @spec get_container_info(GenServer.server(), Integer.t(), String.t()) :: result()
  def get_container_info(conn, service_id, container_id),
    do: call(conn, "browse/browse", %{"sid" => service_id, "cid" => container_id})

  defp start_connection(opts) do
    case Process.whereis(Droom.HEOSSupervisor) do
      nil -> Connection.start_link(opts)
      _ -> DynamicSupervisor.start_child(Droom.HEOSSupervisor, {Connection, opts})
    end
  end
end
