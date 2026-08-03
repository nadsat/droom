defmodule Droom.UPnP.SOAPTest do
  use ExUnit.Case, async: true

  alias Droom.UPnP.SOAP

  test "service_type maps aliases to full types" do
    assert SOAP.service_type(:av) == "urn:schemas-upnp-org:service:AVTransport:1"
    assert SOAP.service_type(:rendering) == "urn:schemas-upnp-org:service:RenderingControl:1"
    assert SOAP.service_type("urn:custom") == "urn:custom"
  end

  test "soap_action builds the SOAPACTION header value" do
    assert SOAP.soap_action(:av, "Play") == "urn:schemas-upnp-org:service:AVTransport:1#Play"
  end

  test "builds a self-closing Pause envelope" do
    body = SOAP.envelope(:av, "Pause")

    assert body =~ "<u:Pause xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>"
    assert body =~ "<s:Body>"
    assert body =~ ~s(xmlns:s="http://schemas.xmlsoap.org/soap/envelope/")
  end

  test "builds an envelope with arguments" do
    body = SOAP.envelope(:av, "Play", %{"Speed" => "1"})

    assert body =~ "<u:Play xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"
    assert body =~ "<Speed>1</Speed>"
  end

  test "escapes argument values" do
    body = SOAP.envelope(:av, "SetAVTransportURI", %{"CurrentURI" => "http://h/a&b<c>d"})
    assert body =~ "http://h/a&amp;b&lt;c&gt;d"
  end

  test "parses a response with fields" do
    body =
      ~s|<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><CurrentVolume>30</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>|

    assert {:ok, %{"CurrentVolume" => "30"}} = SOAP.parse_response(body)
  end

  test "parses an empty response element" do
    body =
      ~s|<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:PlayResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/></s:Body></s:Envelope>|

    assert {:ok, %{}} = SOAP.parse_response(body)
  end

  test "parses an encoding-declared response" do
    body =
      ~s|<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1"><CurrentMute>0</CurrentMute></u:GetMuteResponse></s:Body></s:Envelope>|

    assert {:ok, %{"CurrentMute" => "0"}} = SOAP.parse_response(body)
  end

  test "parses a fault into an upnp_error" do
    body =
      ~s|<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>701</errorCode><errorDescription>Invalid InstanceID</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>|

    assert {:error, {:upnp_error, 701, "Invalid InstanceID"}} = SOAP.parse_response(body)
  end

  test "handles malformed XML" do
    assert {:error, _} = SOAP.parse_response("not xml at all")
  end

  test "handles non-XML content" do
    assert {:error, _} = SOAP.parse_response("<s:Envelope>")
  end
end
