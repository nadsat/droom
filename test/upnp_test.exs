defmodule Droom.UPnPTest do
  use ExUnit.Case, async: false

  alias Droom.Test.MockUPnP
  alias Droom.UPnP.{AVTransport, Connection, RenderingControl}

  setup do
    {:ok, fake} = MockUPnP.start_link()
    {:ok, conn} = Droom.UPnP.connect(MockUPnP.description_url(fake))
    %{fake: fake, conn: conn}
  end

  test "connects and exposes the device description", %{conn: conn} do
    assert %{friendly_name: "Test Renderer"} = Connection.description(conn)
  end

  test "play posts a SOAP request", %{fake: fake, conn: conn} do
    assert AVTransport.play(conn) == :ok

    assert [request] = posts(fake)
    assert request.method == "POST"
    assert request.path == "/control/AVTransport"
    assert request.headers["soapaction"] == ~s("urn:schemas-upnp-org:service:AVTransport:1#Play")
    assert request.body =~ "<u:Play"
    assert request.body =~ "<InstanceID>0</InstanceID>"
  end

  test "set_av_transport_uri passes the uri", %{fake: fake, conn: conn} do
    assert AVTransport.set_av_transport_uri(conn, "http://example.com/song.mp3") == :ok

    assert [request] = posts(fake)
    assert request.headers["soapaction"] =~ "#SetAVTransportURI"
    assert request.body =~ "<CurrentURI>http://example.com/song.mp3</CurrentURI>"
  end

  test "pause, stop, next and previous post the right actions", %{fake: fake, conn: conn} do
    assert AVTransport.pause(conn) == :ok
    assert AVTransport.stop(conn) == :ok
    assert AVTransport.next(conn) == :ok
    assert AVTransport.previous(conn) == :ok

    assert Enum.map(posts(fake), & &1.headers["soapaction"]) == [
             ~s("urn:schemas-upnp-org:service:AVTransport:1#Pause"),
             ~s("urn:schemas-upnp-org:service:AVTransport:1#Stop"),
             ~s("urn:schemas-upnp-org:service:AVTransport:1#Next"),
             ~s("urn:schemas-upnp-org:service:AVTransport:1#Previous")
           ]
  end

  test "seek posts Unit and Target", %{fake: fake, conn: conn} do
    assert AVTransport.seek(conn, "REL_TIME", "00:01:00") == :ok

    assert [request] = posts(fake)
    assert request.headers["soapaction"] =~ "#Seek"
    assert request.body =~ "<Unit>REL_TIME</Unit>"
    assert request.body =~ "<Target>00:01:00</Target>"
  end

  test "get_transport_state returns the current state", %{conn: conn} do
    assert {:ok, "PLAYING"} = AVTransport.get_transport_state(conn)
  end

  test "get_position_info returns track fields", %{conn: conn} do
    assert {:ok, info} = AVTransport.get_position_info(conn)
    assert info["Track"] == "1"
    assert info["TrackURI"] == "http://example.com/song.mp3"
  end

  test "volume get and set", %{fake: fake, conn: conn} do
    assert {:ok, %{"level" => 30, "channel" => "Master"}} = RenderingControl.get_volume(conn)
    assert RenderingControl.set_volume(conn, 42) == :ok

    assert Enum.any?(posts(fake), fn request ->
             request.headers["soapaction"] ==
               ~s("urn:schemas-upnp-org:service:RenderingControl:1#SetVolume") and
               request.body =~ "<DesiredVolume>42</DesiredVolume>"
           end)
  end

  test "mute get and set", %{fake: fake, conn: conn} do
    assert {:ok, %{"mute" => false, "channel" => "Master"}} = RenderingControl.get_mute(conn)
    assert RenderingControl.set_mute(conn, true) == :ok

    assert Enum.any?(posts(fake), fn request ->
             request.headers["soapaction"] =~ "#SetMute" and
               request.body =~ "<DesiredMute>1</DesiredMute>"
           end)
  end

  test "surfaces UPnP errors" do
    {:ok, fake} = MockUPnP.start_link(fail: ["SetVolume"])
    {:ok, conn} = Droom.UPnP.connect(MockUPnP.description_url(fake))

    assert {:error, {:upnp_error, 701, "Invalid Action"}} = RenderingControl.set_volume(conn, 42)
  end

  test "close stops the connection", %{conn: conn} do
    assert :ok = Droom.UPnP.close(conn)
    refute Process.alive?(conn)
  end

  defp posts(fake) do
    fake
    |> MockUPnP.requests()
    |> Enum.filter(&(&1.method == "POST"))
  end
end
