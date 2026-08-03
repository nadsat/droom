defmodule Droom.Events do
  @moduledoc """
  Topic helpers and broadcasting for discovery and device events.

  Events are distributed through `Phoenix.PubSub` under the `Droom.PubSub`
  server. Discovery messages are `{:device_found, device}` /
  `{:device_lost, usn, device}` tuples; HEOS messages are
  `{:heos_event, command, params, payload}` tuples.

  Topics:

    * `droom:discovery` — found and lost devices
    * `droom:heos` — HEOS change events
  """

  @prefix "droom"

  @type topic :: :discovery | :heos

  @doc "Returns the pubsub topic for a high-level topic selector."
  @spec topic(topic()) :: String.t()
  def topic(:discovery), do: @prefix <> ":discovery"
  def topic(:heos), do: @prefix <> ":heos"

  @doc "Broadcasts a message on a topic."
  @spec broadcast(topic(), term()) :: :ok | {:error, term()}
  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Droom.PubSub, topic(topic), message)
  end
end
