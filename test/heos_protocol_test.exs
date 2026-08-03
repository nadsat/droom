defmodule Droom.HEOSProtocolTest do
  use ExUnit.Case, async: true

  alias Droom.HEOS.Protocol

  describe "command/2" do
    test "builds a command with no params" do
      assert Protocol.command("system/heart_beat") == "heos://system/heart_beat"
    end

    test "builds a command with map params, sorted by key" do
      assert Protocol.command("player/set_volume", %{"pid" => 1, "level" => 25}) ==
               "heos://player/set_volume?level=25&pid=1"
    end

    test "builds a command with keyword params" do
      assert Protocol.command("player/set_play_state", pid: 1, state: "play") ==
               "heos://player/set_play_state?pid=1&state=play"
    end

    test "coerces values to strings" do
      assert Protocol.command("player/set_volume", %{"pid" => 1, "level" => 42}) ==
               "heos://player/set_volume?level=42&pid=1"
    end

    test "percent-encodes &, = and %" do
      assert Protocol.command("browse/search", %{"search" => "a&b=c%d"}) ==
               "heos://browse/search?search=a%26b%3Dc%25d"
    end
  end

  describe "parse_message/1" do
    test "parses a success response with payload" do
      message = %{
        "heos" => %{"command" => "player/get_players", "result" => "success", "message" => ""},
        "payload" => [%{"pid" => 1, "name" => "Kitchen"}]
      }

      assert {:ok, parsed} = Protocol.parse_message(message)
      assert parsed.command == "player/get_players"
      assert parsed.result == "success"
      assert parsed.message == ""
      assert parsed.payload == [%{"pid" => 1, "name" => "Kitchen"}]
    end

    test "parses a fail response" do
      message = %{
        "heos" => %{
          "command" => "player/set_volume",
          "result" => "fail",
          "message" => "eid=7&text=Command not executed"
        }
      }

      assert {:ok, parsed} = Protocol.parse_message(message)
      assert parsed.command == "player/set_volume"
      assert parsed.result == "fail"
      assert parsed.message == "eid=7&text=Command not executed"
      assert parsed.payload == nil
    end

    test "parses an event" do
      message = %{
        "heos" => %{"command" => "event/player_state_changed", "message" => "pid=1"},
        "payload" => %{"pid" => 1, "state" => "play"}
      }

      assert {:ok, %{command: "event/player_state_changed"}} = Protocol.parse_message(message)
    end

    test "rejects non-HEOS messages" do
      assert Protocol.parse_message(%{"foo" => "bar"}) == :error
      assert Protocol.parse_message(%{"heos" => %{}}) == :error
      assert Protocol.parse_message("nope") == :error
    end
  end

  describe "parse_params/1" do
    test "parses key=value pairs" do
      assert Protocol.parse_params("pid=1&level=25") == %{"pid" => "1", "level" => "25"}
    end

    test "percent-decodes values" do
      assert Protocol.parse_params("search=a%26b%3Dc%25d") == %{"search" => "a&b=c%d"}
    end

    test "handles empty and nil input" do
      assert Protocol.parse_params("") == %{}
      assert Protocol.parse_params(nil) == %{}
    end
  end

  describe "error_from_message/1" do
    test "extracts eid and text" do
      assert Protocol.error_from_message("eid=7&text=Command not executed") ==
               {:heos_error, 7, "Command not executed"}
    end

    test "falls back to syserrno" do
      assert Protocol.error_from_message("eid=12&syserrno=2") ==
               {:heos_error, 12, "System Error (2)"}
    end

    test "reports a missing eid" do
      assert Protocol.error_from_message("text=Something broke") ==
               {:heos_error, nil, "Something broke"}
    end
  end
end
