defmodule Droom.Test.MockHEOS do
  @moduledoc """
  An in-memory fake HEOS speaker for tests.

  Listens on an ephemeral TCP port and answers HEOS CLI commands with
  pretty-printed JSON responses. Records every command received (see
  `commands/1`). Options:

    * `:fail` — list of command paths that respond with a HEOS error
      (e.g. `["player/set_volume"]`)
    * `:defer` — a command path whose response is preceded by a
      `"command under process"` acknowledgement
    * `:drop_after` — a command path after whose response the connection is
      closed, to exercise reconnection
  """

  use GenServer

  alias Droom.HEOS.Protocol

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "The port the fake speaker is listening on."
  def port(pid), do: GenServer.call(pid, :port)

  @doc "The host the fake speaker claims to be."
  def host(_pid), do: "127.0.0.1"

  @doc "The list of command strings received so far."
  def commands(pid), do: GenServer.call(pid, :commands)

  @impl true
  def init(opts) do
    fail = Keyword.get(opts, :fail, [])
    defer = Keyword.get(opts, :defer)
    drop_after = Keyword.get(opts, :drop_after)

    listen_opts = [:binary, {:packet, :raw}, {:active, false}, {:reuseaddr, true}]

    with {:ok, listen_socket} <- :gen_tcp.listen(0, listen_opts) do
      {:ok, {_addr, port}} = :inet.sockname(listen_socket)
      parent = self()

      spawn_link(fn ->
        accept_loop(listen_socket, parent, %{fail: fail, defer: defer, drop_after: drop_after})
      end)

      {:ok, %{port: port, commands: []}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}
  def handle_call(:commands, _from, state), do: {:reply, state.commands, state}

  @impl true
  def handle_info({:command, command}, state) do
    {:noreply, %{state | commands: state.commands ++ [command]}}
  end

  defp accept_loop(listen_socket, fake, opts) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        handler = spawn_link(fn -> handler(socket, fake, opts) end)
        :gen_tcp.controlling_process(socket, handler)
        accept_loop(listen_socket, fake, opts)

      {:error, _reason} ->
        :ok
    end
  end

  defp handler(socket, fake, opts) do
    case read_command(socket, "") do
      {:ok, command} ->
        send(fake, {:command, command})
        {path, _params} = split_command(command)
        :gen_tcp.send(socket, response(command, opts))

        if path == opts.defer do
          :gen_tcp.send(socket, success(path, payload(path, command)))
        end

        if path == "system/register_for_change_events" do
          :gen_tcp.send(socket, event_message())
        end

        if command == opts.drop_after, do: :gen_tcp.close(socket)
        handler(socket, fake, opts)

      {:error, _reason} ->
        :gen_tcp.close(socket)
    end
  end

  defp read_command(socket, buffer) do
    case String.split(buffer, "\r\n") do
      [complete | _] when complete != buffer ->
        {:ok, complete}

      _ ->
        case :gen_tcp.recv(socket, 0, 10_000) do
          {:ok, data} -> read_command(socket, buffer <> data)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp response(command, opts) do
    {path, _params} = split_command(command)

    cond do
      command in opts.fail or path in opts.fail -> fail(path)
      path == opts.defer -> deferred(path)
      true -> success(path, payload(path, command))
    end
  end

  defp split_command(command) do
    case String.split(command, "?") do
      [path] -> {String.trim_leading(path, "heos://"), %{}}
      [path, query] -> {String.trim_leading(path, "heos://"), Protocol.parse_params(query)}
    end
  end

  defp success(path, nil),
    do: encode(%{"heos" => %{"command" => path, "result" => "success", "message" => ""}})

  defp success(path, payload),
    do:
      encode(%{
        "heos" => %{"command" => path, "result" => "success", "message" => ""},
        "payload" => payload
      })

  defp deferred(path) do
    encode(%{
      "heos" => %{"command" => path, "result" => "success", "message" => "command under process"}
    })
  end

  defp fail(path) do
    encode(%{
      "heos" => %{
        "command" => path,
        "result" => "fail",
        "message" => "eid=7&text=Command not executed"
      }
    })
  end

  defp event_message do
    encode(%{
      "heos" => %{"command" => "event/player_state_changed", "message" => "pid=1"},
      "payload" => %{"pid" => 1, "state" => "play"}
    })
  end

  defp encode(json), do: Jason.encode!(json, pretty: true) <> "\r\n\r\n"

  defp payload(path, _command) do
    case path do
      "player/get_players" ->
        [player(1, "Kitchen"), player(2, "Living Room")]

      "player/get_player_info" ->
        player(1, "Kitchen")

      "player/get_play_state" ->
        %{"pid" => 1, "state" => "play"}

      "player/get_now_playing_media" ->
        %{
          "pid" => 1,
          "type" => "song",
          "album" => "Test Album",
          "artist" => "Test Artist",
          "song" => "Test Song",
          "image_url" => "http://example.com/art.jpg",
          "qid" => -1,
          "sid" => -1
        }

      "player/get_volume" ->
        %{"pid" => 1, "level" => 30, "mute" => "off"}

      "player/get_mute" ->
        %{"pid" => 1, "state" => "off"}

      "player/get_queue" ->
        %{"pid" => 1, "qid" => -1, "count" => 0, "returned" => 0}

      "group/get_groups" ->
        [
          %{
            "gid" => 101,
            "name" => "Whole House",
            "players" => [%{"pid" => 1}, %{"pid" => 2}]
          }
        ]

      _ ->
        nil
    end
  end

  defp player(pid, name) do
    %{
      "name" => name,
      "pid" => pid,
      "model" => "HEOS Drive",
      "version" => "1.0.0",
      "network" => "wired",
      "lineout" => pid,
      "serial" => "HEOS-#{pid}",
      "ip" => "192.168.1.1#{pid}"
    }
  end
end
