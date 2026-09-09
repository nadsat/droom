defmodule Droom.HEOSTest do
  use ExUnit.Case, async: false

  alias Droom.HEOS
  alias Droom.Test.{MockHEOS, MockHEOSResponder}

  setup do
    {:ok, fake} = MockHEOS.start_link()
    {:ok, conn} = HEOS.connect(MockHEOS.host(fake), port: MockHEOS.port(fake))
    %{fake: fake, conn: conn}
  end

  test "connects and confirms with heart_beat", %{conn: conn} do
    assert HEOS.heart_beat(conn) == :ok
  end

  test "get_players returns the player list", %{conn: conn} do
    assert {:ok, [player | _]} = HEOS.get_players(conn)
    assert player["name"] == "Kitchen"
    assert player["pid"] == 1
  end

  test "get_play_state and set_play_state", %{fake: fake, conn: conn} do
    assert {:ok, %{"pid" => 1, "state" => "play"}} = HEOS.get_play_state(conn, 1)

    assert HEOS.set_play_state(conn, 1, "pause") == :ok
    assert HEOS.play(conn, 1) == :ok
    assert HEOS.pause(conn, 1) == :ok
    assert HEOS.stop(conn, 1) == :ok

    assert commands(fake) == [
             "heos://player/get_play_state?pid=1",
             "heos://player/set_play_state?pid=1&state=pause",
             "heos://player/set_play_state?pid=1&state=play",
             "heos://player/set_play_state?pid=1&state=pause",
             "heos://player/set_play_state?pid=1&state=stop"
           ]
  end

  test "get_now_playing_media returns track fields", %{conn: conn} do
    assert {:ok, media} = HEOS.get_now_playing_media(conn, 1)
    assert media["song"] == "Test Song"
    assert media["artist"] == "Test Artist"
  end

  test "volume get and set", %{fake: fake, conn: conn} do
    assert {:ok, %{"level" => 30, "mute" => "off", "pid" => 1}} = HEOS.get_volume(conn, 1)
    assert HEOS.set_volume(conn, 1, 42) == :ok
    assert HEOS.volume_up(conn, 1) == :ok
    assert HEOS.volume_down(conn, 1) == :ok

    assert commands(fake) == [
             "heos://player/get_volume?pid=1",
             "heos://player/set_volume?level=42&pid=1",
             "heos://player/volume_up?pid=1",
             "heos://player/volume_down?pid=1"
           ]
  end

  test "mute get and set", %{fake: fake, conn: conn} do
    assert {:ok, %{"state" => "off", "pid" => 1}} = HEOS.get_mute(conn, 1)
    assert HEOS.set_mute(conn, 1, "on") == :ok

    assert commands(fake) == [
             "heos://player/get_mute?pid=1",
             "heos://player/set_mute?pid=1&state=on"
           ]
  end

  test "get_queue and get_groups", %{conn: conn} do
    assert {:ok, %{"count" => 0}} = HEOS.get_queue(conn, 1)

    assert {:ok, [group]} = HEOS.get_groups(conn)
    assert group["gid"] == 101
    assert group["name"] == "Whole House"
  end

  test "surfaces HEOS errors" do
    {:ok, fake} = MockHEOS.start_link(fail: ["player/set_volume"])
    {:ok, conn} = HEOS.connect(MockHEOS.host(fake), port: MockHEOS.port(fake))

    assert {:error, {:heos_error, 7, "Command not executed"}} = HEOS.set_volume(conn, 1, 42)
  end

  test "waits through a 'command under process' response", %{conn: _conn} do
    {:ok, fake} = MockHEOS.start_link(defer: "player/get_play_state")
    {:ok, conn} = HEOS.connect(MockHEOS.host(fake), port: MockHEOS.port(fake))

    assert {:ok, %{"pid" => 1, "state" => "play"}} = HEOS.get_play_state(conn, 1)
  end

  test "returns the real data when the deferred ack carries a payload", %{conn: _conn} do
    {:ok, fake} =
      MockHEOS.start_link(defer: "browse/get_containers", defer_payload: true)

    {:ok, conn} = HEOS.connect(MockHEOS.host(fake), port: MockHEOS.port(fake))

    assert {:ok, [container | _]} = HEOS.call(conn, "browse/get_containers")
    assert container["type"] == "station"
  end

  test "broadcasts events after register_for_change_events", %{conn: conn} do
    HEOS.subscribe()
    assert HEOS.register_for_change_events(conn) == :ok

    assert_receive {:heos_event, "event/player_state_changed", %{"pid" => "1"},
                    %{"state" => "play"}},
                   1_000
  end

  test "reconnects after a dropped connection" do
    {:ok, fake} = MockHEOS.start_link(drop_after: "player/get_volume")
    {:ok, conn} = HEOS.connect(MockHEOS.host(fake), port: MockHEOS.port(fake))

    assert {:ok, %{"level" => 30}} = HEOS.get_volume(conn, 1)
    assert :ok = HEOS.reconnect(conn)
    assert HEOS.heart_beat(conn) == :ok
  end

  test "close stops the connection", %{conn: conn} do
    assert :ok = HEOS.close(conn)
    refute Process.alive?(conn)
  end

  describe "discover/1" do
    test "searches for the HEOS search target" do
      {:ok, responder} = MockHEOSResponder.start_link()

      opts = [
        target_ip: {127, 0, 0, 1},
        target_port: MockHEOSResponder.port(responder),
        source_port: 0,
        timeout: 1_500
      ]

      assert {:ok, [device]} = HEOS.discover(opts)
      assert device.usn =~ "denon-001"
      assert device.host == "192.168.1.10"
      assert device.port == 1255

      assert [request] = MockHEOSResponder.requests(responder)
      assert request =~ "ST: urn:schemas-denon-com:device:ACT-Denon:1"
    end
  end

  defp commands(fake), do: MockHEOS.commands(fake)
end
