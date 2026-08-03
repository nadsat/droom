defmodule Droom.DiscoveryTest do
  use ExUnit.Case, async: false

  alias Droom.{Device, Discovery}
  alias Droom.Test.FakeResponder

  test "one-shot discovery finds devices" do
    {:ok, responder} = FakeResponder.start_link()

    opts = [
      target_ip: {127, 0, 0, 1},
      target_port: FakeResponder.port(responder),
      source_port: 0,
      timeout: 1_500
    ]

    assert {:ok, [device]} = Droom.UPnP.discover(opts)
    assert %Device{} = device
    assert device.host == "192.168.1.10"
    assert device.port == 8080
    assert device.usn =~ "uuid:123-456"
    assert device.st =~ "MediaRenderer"
  end

  test "continuous discovery announces found and lost devices" do
    Droom.UPnP.subscribe(:discovery)

    {:ok, discovery} = Droom.UPnP.start_discovery(source_port: 0, interval: 60_000)
    port = Discovery.local_port(discovery)

    {:ok, sender} = :gen_udp.open(0, [:binary])

    :ok = :gen_udp.send(sender, {127, 0, 0, 1}, port, notify(:alive))
    assert_receive {:device_found, %Device{usn: usn}}, 1_000
    assert usn =~ "uuid:123-456"

    assert Enum.any?(Discovery.devices(discovery), &(&1.usn == usn))

    :ok = :gen_udp.send(sender, {127, 0, 0, 1}, port, notify(:byebye))
    assert_receive {:device_lost, ^usn, %Device{}}, 1_000

    refute Enum.any?(Discovery.devices(discovery), &(&1.usn == usn))
  end

  test "parses SSDP messages" do
    message =
      "NOTIFY * HTTP/1.1\r\n" <>
        "HOST: 239.255.255.250:1900\r\n" <>
        "NT: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" <>
        "NTS: ssdp:byebye\r\n" <>
        "USN: uuid:123-456::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"

    parsed = Droom.SSDP.parse(message)
    assert Droom.SSDP.byebye?(parsed)
    assert parsed.headers["usn"] == "uuid:123-456::urn:schemas-upnp-org:device:MediaRenderer:1"
  end

  defp notify(:alive) do
    "NOTIFY * HTTP/1.1\r\n" <>
      "HOST: 239.255.255.250:1900\r\n" <>
      "NT: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" <>
      "NTS: ssdp:alive\r\n" <>
      "LOCATION: http://192.168.1.10:8080/upnp/desc/device_description.xml\r\n" <>
      "USN: uuid:123-456::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
  end

  defp notify(:byebye) do
    "NOTIFY * HTTP/1.1\r\n" <>
      "HOST: 239.255.255.250:1900\r\n" <>
      "NT: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" <>
      "NTS: ssdp:byebye\r\n" <>
      "USN: uuid:123-456::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
  end
end
