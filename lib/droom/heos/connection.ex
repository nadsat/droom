defmodule Droom.HEOS.Connection do
  @moduledoc """
  A TCP connection to a HEOS speaker running the HEOS CLI protocol.

  One connection to any speaker in the system exposes every player, group and
  queue on the network. Commands are serialized: only one command is in flight
  at a time, matching the protocol's lack of request IDs. The response to a
  command is correlated by its echoed command name; any unsolicited
  `event/...` messages received in the meantime are broadcast on the
  `droom:heos` topic (see `Droom.HEOS.subscribe/0`).

  Responses arrive as pretty-printed JSON that may span many lines and be
  split across TCP packets; a line buffer reassembles them and messages are
  dispatched as soon as the JSON parses or a blank line terminator is seen.

  Connections are normally started via `Droom.HEOS.connect/2`.
  """

  use GenServer, restart: :temporary

  alias Droom.{Events, HEOS.Protocol}

  @default_port 1255
  @default_timeout 5_000

  defstruct [
    :socket,
    :host,
    :port,
    :buffer,
    :pending_command,
    :pending_json,
    :awaiting
  ]

  @type result ::
          :ok
          | {:ok, term()}
          | {:error, {:heos_error, non_neg_integer() | nil, String.t()}}
          | {:error, :timeout | :busy | :disconnected | term()}

  @doc "Starts a HEOS CLI connection process. `:host` is required."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @doc """
  Sends a CLI command and waits for its response.

  `command` is a `command_group/command` path (e.g. `"player/set_volume"`);
  `params` are its attributes. Options:

    * `:timeout` — milliseconds to wait for the response (default `5000`)

  Returns `:ok` when the response has neither payload nor message params,
  `{:ok, payload}` or `{:ok, params}` otherwise, `{:error, {:heos_error, code,
  text}}` for a failed command and `{:error, :timeout}` /
  `{:error, {:disconnected, reason}}` for transport problems.
  """
  @spec call(GenServer.server(), String.t(), map() | keyword() | nil, keyword()) :: result()
  def call(server, command, params \\ nil, opts \\ []) do
    GenServer.call(server, {:command, command, params, opts}, :infinity)
  end

  @doc "Re-establishes the TCP connection after it was dropped."
  @spec reconnect(GenServer.server()) :: :ok | {:error, term()}
  def reconnect(server), do: GenServer.call(server, :reconnect)

  @doc "Closes the connection."
  @spec close(GenServer.server()) :: :ok
  def close(server), do: GenServer.stop(server, :normal)

  @impl true
  def init(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.get(opts, :port, @default_port)
    timeout = Keyword.get(opts, :connect_timeout, @default_timeout)

    case connect(host, port, timeout) do
      {:ok, socket} ->
        state = %__MODULE__{
          socket: socket,
          host: host,
          port: port,
          buffer: "",
          pending_command: nil,
          pending_json: ""
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:connect_failed, reason}}
    end
  end

  @impl true
  def handle_call({:command, command, params, opts}, from, state) do
    case state.socket do
      nil ->
        {:reply, {:error, :disconnected}, state}

      socket ->
        if state.awaiting do
          {:reply, {:error, :busy}, state}
        else
          request = Protocol.command(command, params) <> "\r\n"

          case :gen_tcp.send(socket, request) do
            :ok ->
              awaiting = %{
                from: from,
                command: command,
                token: make_ref(),
                ref: Process.monitor(elem(from, 0))
              }

              timeout = Keyword.get(opts, :timeout, @default_timeout)
              awaiting = Map.put(awaiting, :timer, schedule_timeout(awaiting.token, timeout))
              {:noreply, %{state | awaiting: awaiting}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
    end
  end

  def handle_call(:reconnect, _from, %__MODULE__{host: host, port: port} = state) do
    case connect(host, port, @default_timeout) do
      {:ok, socket} ->
        {:reply, :ok,
         %{state | socket: socket, buffer: "", pending_command: nil, pending_json: ""}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %__MODULE__{socket: socket} = state) do
    {:noreply, process_data(state, data)}
  end

  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    {:noreply, handle_disconnect(state, :closed)}
  end

  def handle_info({:tcp_error, socket, reason}, %__MODULE__{socket: socket} = state) do
    {:noreply, handle_disconnect(state, reason)}
  end

  def handle_info(
        {:command_timeout, token},
        %__MODULE__{awaiting: %{token: token} = awaiting} = state
      ) do
    reply(awaiting, {:error, :timeout})
    {:noreply, %{state | awaiting: nil}}
  end

  def handle_info({:command_timeout, _token}, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %__MODULE__{awaiting: %{ref: ref} = awaiting} = state
      ) do
    Process.cancel_timer(awaiting.timer)
    {:noreply, %{state | awaiting: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # -- line framing ---------------------------------------------------------

  defp process_data(state, data) do
    buffer = state.buffer <> data
    {lines, rest} = split_lines(buffer)

    lines
    |> Enum.reduce(%{state | buffer: rest}, &process_line(&2, &1))
  end

  defp split_lines(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts)}
  end

  defp process_line(state, line) do
    line = String.trim_trailing(line, "\r")

    cond do
      String.starts_with?(line, "heos://") ->
        state
        |> finalize_message()
        |> Map.put(:pending_command, String.trim_leading(line, "heos://"))
        |> Map.put(:pending_json, "")

      line == "" ->
        finalize_message(state)

      state.pending_json != "" or String.starts_with?(line, "{") ->
        state
        |> update_in([Access.key(:pending_json)], &(&1 <> line <> "\n"))
        |> maybe_finalize()

      true ->
        state
    end
  end

  defp maybe_finalize(state) do
    case Jason.decode(state.pending_json) do
      {:ok, _message} -> finalize_message(state)
      _ -> state
    end
  end

  defp finalize_message(%__MODULE__{pending_json: json} = state) when json == "" do
    %{state | pending_command: nil, pending_json: ""}
  end

  defp finalize_message(state) do
    json = state.pending_json
    state = %{state | pending_command: nil, pending_json: ""}

    case Jason.decode(json) do
      {:ok, message} -> dispatch(state, message)
      _ -> state
    end
  end

  # -- message dispatch ------------------------------------------------------

  defp dispatch(state, message) do
    case Protocol.parse_message(message) do
      {:ok, %{command: command} = msg} when is_binary(command) ->
        command = String.trim_leading(command, "heos://")

        if String.starts_with?(command, "event/") do
          Events.broadcast(
            :heos,
            {:heos_event, command, Protocol.parse_params(msg.message), msg.payload}
          )

          state
        else
          handle_response(state, %{msg | command: command})
        end

      _ ->
        state
    end
  end

  defp handle_response(
         %__MODULE__{awaiting: %{command: awaited}} = state,
         %{command: command} = msg
       )
       when command == awaited do
    cond do
      msg.result == "fail" ->
        reply_awaiting(state, {:error, Protocol.error_from_message(msg.message)})

      deferred?(msg) ->
        # "command under process": the real response arrives later.
        state

      true ->
        reply_awaiting(state, normalize(msg))
    end
  end

  defp handle_response(state, _msg), do: state

  defp deferred?(%{result: "success", message: "command under process", payload: payload}) do
    payload in [nil, "", %{}, []]
  end

  defp deferred?(_), do: false

  defp normalize(%{payload: payload, message: message}) do
    cond do
      is_map(payload) and map_size(payload) > 0 ->
        {:ok, payload}

      is_list(payload) and payload != [] ->
        {:ok, payload}

      true ->
        case Protocol.parse_params(message) do
          params when map_size(params) > 0 -> {:ok, params}
          _ -> :ok
        end
    end
  end

  # -- connection upkeep -----------------------------------------------------

  defp reply_awaiting(%__MODULE__{awaiting: awaiting} = state, result) do
    reply(awaiting, result)
    %{state | awaiting: nil}
  end

  defp reply(awaiting, result) do
    GenServer.reply(awaiting.from, result)
    Process.demonitor(awaiting.ref, [:flush])
  end

  defp schedule_timeout(token, timeout) do
    Process.send_after(self(), {:command_timeout, token}, timeout)
  end

  defp handle_disconnect(%__MODULE__{awaiting: awaiting} = state, reason) do
    if awaiting, do: reply(awaiting, {:error, {:disconnected, reason}})

    %{state | socket: nil, buffer: "", pending_command: nil, pending_json: "", awaiting: nil}
  end

  defp connect(host, port, timeout) do
    host = if is_binary(host), do: String.to_charlist(host), else: host
    :gen_tcp.connect(host, port, [:binary, {:active, true}, {:nodelay, true}], timeout)
  end
end
