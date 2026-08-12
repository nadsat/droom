# Droom
This is a WIP Elixir library for controlling UPnP/DLNA media renderers and Denon HEOS speakers.
UPnP/DLNA devices are controlled over plain SOAP/HTTP, while Denon HEOS speakers are controlled over the HEOS CLI protocol.

The top-level `Droom` module is the common entry point for protocol-agnostic
operations: `Droom.discover/1` runs a one-shot SSDP search and
`Droom.subscribe/1` / `Droom.unsubscribe/1` attach to the discovery and HEOS
event topics.

## UPnP/DLNA

Devices are located with SSDP discovery (`Droom.UPnP.discover/1`,
`Droom.UPnP.start_discovery/1`) and controlled through the standard UPnP
services:

  * **AVTransport** — `SetAVTransportURI`, `Play`, `Pause`, `Stop`, `Seek`,
    `Next`, `Previous`, `GetTransportInfo`, `GetPositionInfo`, `GetMediaInfo`
  * **RenderingControl** — `GetVolume`, `SetVolume`, `GetMute`, `SetMute`

## HEOS

HEOS speakers expose the HEOS CLI, a newline-terminated TCP protocol on port
`1255`. A single connection to any speaker in the system controls every
player, group and queue on the network. Speakers are discovered via SSDP
(`urn:schemas-denon-com:device:ACT-Denon:1`) with `Droom.HEOS.discover/1`.

Commands available on `Droom.HEOS`:

  * players — `get_players/1`, `get_player_info/2`, `get_play_state/2`,
    `set_play_state/3`, `play/2`, `pause/2`, `stop/2`, `toggle_play_pause/2`,
    `get_now_playing_media/2`, `get_queue/2`, `play_queue/3`
  * volume — `get_volume/2`, `set_volume/3`, `volume_up/2`, `volume_down/2`,
    `get_mute/2`, `set_mute/3`
  * groups — `get_groups/1`
  * system — `heart_beat/1`, `register_for_change_events/1`,
    `reconnect/1`, `close/1`

Change events are broadcast on the `:heos` topic after
`register_for_change_events/1`; subscribe with `Droom.HEOS.subscribe/0`.


### Key behaviors:

- One SOAP action per call; the connection holds the AVTransport and
  RenderingControl control URLs extracted from the device description.
- Relative control URLs are resolved against the description URL.
- SOAP faults (HTTP 500 with an `UPnPError` body) surface as
  `{:error, {:upnp_error, code, description}}`.
- HEOS commands are serialized over a single TCP connection and correlated
  by their echoed command name; HEOS errors surface as
  `{:error, {:heos_error, code, text}}`.
- Unsolicited HEOS change events (`event/...`) are broadcast on the `:heos`
  topic as `{:heos_event, command, params, payload}`.

## Usage

### UPnP

```elixir
{:ok, [device | _]} = Droom.UPnP.discover()
{:ok, conn} = Droom.UPnP.connect(device)

Droom.UPnP.AVTransport.set_av_transport_uri(conn, "http://media.example.com/song.mp3")
Droom.UPnP.AVTransport.play(conn)

{:ok, %{"level" => volume}} = Droom.UPnP.RenderingControl.get_volume(conn)
Droom.UPnP.RenderingControl.set_volume(conn, 30)
```

### HEOS

```elixir
{:ok, [device | _]} = Droom.HEOS.discover()
{:ok, conn} = Droom.HEOS.connect(device)

{:ok, [player | _]} = Droom.HEOS.get_players(conn)
Droom.HEOS.play(conn, player["pid"])
{:ok, %{"level" => volume}} = Droom.HEOS.get_volume(conn, player["pid"])
```

## Continuous discovery

```elixir
{:ok, discovery} = Droom.UPnP.start_discovery()
Droom.subscribe(:discovery)

receive do
  {:device_found, device} -> IO.inspect(device)
  {:device_lost, usn, device} -> IO.inspect({usn, device})
end
```
