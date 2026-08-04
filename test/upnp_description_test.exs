defmodule Droom.UPnP.DescriptionTest do
  use ExUnit.Case, async: true

  alias Droom.Test.MockUPnP
  alias Droom.UPnP.{Description, SOAP}

  @av "urn:schemas-upnp-org:service:AVTransport:1"
  @rendering "urn:schemas-upnp-org:service:RenderingControl:1"

  test "parses a device description and resolves relative control URLs" do
    xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <device>
        <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
        <friendlyName>Living Room</friendlyName>
        <manufacturer>Acme</manufacturer>
        <modelName>RenderOne</modelName>
        <serviceList>
          <service>
            <serviceType>#{@av}</serviceType>
            <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
            <controlURL>/upnp/control/AVTransport1</controlURL>
            <eventSubURL>/upnp/event/AVTransport1</eventSubURL>
          </service>
          <service>
            <serviceType>#{@rendering}</serviceType>
            <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
            <controlURL>http://192.168.1.50:49152/rc</controlURL>
          </service>
        </serviceList>
      </device>
    </root>
    """

    assert {:ok, description} = Description.parse(xml, "http://192.168.1.50:8080/desc.xml")

    assert description.friendly_name == "Living Room"
    assert description.model_name == "RenderOne"
    assert description.manufacturer == "Acme"

    assert description.services[@av].control_url ==
             "http://192.168.1.50:8080/upnp/control/AVTransport1"

    assert description.services[@av].event_url ==
             "http://192.168.1.50:8080/upnp/event/AVTransport1"

    assert description.services[@rendering].control_url == "http://192.168.1.50:49152/rc"
  end

  test "rejects documents without a device element" do
    assert {:error, :not_a_device_description} = Description.parse("<root></root>")
  end

  test "fetches a description over HTTP" do
    {:ok, fake} = MockUPnP.start_link()

    assert {:ok, description} = Description.fetch(MockUPnP.description_url(fake))
    assert description.friendly_name == "Test Renderer"
    assert description.model_name == "TestModel"

    assert description.services[SOAP.service_type(:av)].control_url ==
             "http://127.0.0.1:#{MockUPnP.port(fake)}/control/AVTransport"

    assert description.services[SOAP.service_type(:rendering)].control_url ==
             "http://127.0.0.1:#{MockUPnP.port(fake)}/control/RenderingControl"
  end
end
