defmodule Jido.SignalTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.ID

  describe "new/1" do
    test "generates a UUID7 and CloudEvents 1.0 specversion" do
      assert {:ok, signal} = Signal.new(type: "example.event", source: "/example")

      assert ID.valid?(signal.id)
      assert signal.specversion == "1.0"
      assert signal.source == "/example"
    end

    test "requires an explicit source" do
      assert {:error, error} = Signal.new(type: "example.event")
      assert error =~ "source"
    end

    test "does not invent time or data content type" do
      assert {:ok, signal} =
               Signal.new(type: "example.event", source: "/example", data: %{value: 1})

      assert signal.time == nil
      assert signal.datacontenttype == nil
    end

    test "accepts an external identifier" do
      assert {:ok, signal} =
               Signal.new(type: "example.event", source: "/example", id: "external-id")

      assert signal.id == "external-id"
    end

    test "keeps key collision and explicit null errors when applying defaults" do
      base = %{type: "example.event", source: "/example"}
      assert {:error, error} = Signal.new(Map.put(base, "type", "other.event"))
      assert error =~ "duplicate attribute"

      for key <- [:id, :specversion] do
        assert {:error, error} = Signal.new(Map.put(base, key, nil))
        assert error =~ Atom.to_string(key)
      end
    end

    test "normalizes mixed keys, legacy versions, extensions, and binary data together" do
      assert {:ok, signal} =
               Signal.new(%{
                 "type" => "example.event",
                 "data_base64" => "AQID",
                 id: "external-id",
                 source: "/example",
                 specversion: "1.0.2",
                 tenant: "one"
               })

      assert signal.id == "external-id"
      assert signal.specversion == "1.0"
      assert signal.extensions == %{"tenant" => "one"}
      assert signal.data == <<1, 2, 3>>
      assert Signal.to_map(signal)["data_base64"] == "AQID"
    end

    test "keeps nested constructor extensions and rejects duplicate flat values" do
      base = %{
        type: "example.event",
        source: "/example",
        extensions: %{tenantid: "tenant-123"}
      }

      assert {:ok, signal} = Signal.new(base)
      assert signal.extensions == %{"tenantid" => "tenant-123"}

      assert {:error, error} = Signal.new(Map.put(base, :tenantid, "other-tenant"))
      assert error =~ "duplicate extension attribute"
      assert error =~ "tenantid"
    end

    test "validates event time and data schema" do
      assert {:ok, signal} =
               Signal.new(
                 type: "example.event",
                 source: "/example",
                 time: "2026-08-26T12:00:00Z",
                 dataschema: "https://example.com/schemas/event"
               )

      assert signal.time == "2026-08-26T12:00:00Z"

      assert {:error, error} =
               Signal.new(type: "example.event", source: "/example", time: "yesterday")

      assert error =~ "RFC 3339"

      assert {:error, error} =
               Signal.new(type: "example.event", source: "/example", dataschema: "/relative")

      assert error =~ "absolute URI"
    end

    test "rejects forbidden CloudEvents String characters without restricting data" do
      wire = %{"specversion" => "1.0", "id" => "one", "type" => "event", "source" => "/test"}

      for codepoint <- [0, 10, 31, 127, 133, 159, 0xFDD0, 0xFDEF, 0xFFFF, 0x1FFFE, 0x10FFFF],
          field <- ["id", "type", "subject"] do
        invalid = Map.put(wire, field, "x" <> <<codepoint::utf8>>)
        assert {:error, _} = Signal.new(invalid)
        assert {:error, _} = Signal.from_map(invalid)
        assert {:error, _} = Signal.deserialize(Jason.encode!(invalid))
      end

      valid = Map.merge(wire, %{"subject" => "café 😀", "data" => "domain\ntext"})
      assert {:ok, signal} = Signal.new(valid)
      assert {:ok, json} = Signal.serialize(signal)
      assert {:ok, ^signal} = Signal.deserialize(json)
    end

    test "validates RFC 3339 text and preserves supported timestamp spelling" do
      wire = %{"specversion" => "1.0", "id" => "one", "type" => "event", "source" => "/test"}

      for time <- [
            "2026-01-01t00:00:00z",
            "2026-01-01T00:00:00.123456789Z",
            "2026-01-01 00:00:00Z",
            "1990-12-31T23:59:60Z",
            "1990-12-31T15:59:60-08:00",
            "1991-01-01T00:59:60+01:00"
          ] do
        attrs = Map.put(wire, "time", time)
        assert {:ok, signal} = Signal.new(attrs)
        assert {:ok, ^signal} = Signal.from_map(attrs)
        assert Signal.to_map(signal)["time"] == time
        assert {:ok, ^signal} = Signal.deserialize(Jason.encode!(attrs))
      end

      for time <- [
            "-0001-01-01T00:00:00Z",
            "2026-01-01T00:00:00,5Z",
            "2026-02-30T00:00:00Z",
            "2026-01-01T00:00:00+24:00",
            "2026-01-01T24:00:00Z",
            "1990-12-31T23:58:60Z",
            "1990-12-30T23:59:60Z"
          ] do
        attrs = Map.put(wire, "time", time)
        assert {:error, _} = Signal.new(attrs)
        assert {:error, _} = Signal.from_map(attrs)
      end
    end

    test "rejects invalid text, URI, and media type values" do
      invalid_utf8 = <<255>>
      base = [type: "example.event", source: "/example"]

      for attributes <- [
            Keyword.put(base, :id, invalid_utf8),
            Keyword.put(base, :source, invalid_utf8),
            Keyword.put(base, :type, invalid_utf8),
            Keyword.put(base, :subject, invalid_utf8),
            Keyword.put(base, :time, invalid_utf8),
            Keyword.put(base, :datacontenttype, invalid_utf8),
            Keyword.put(base, :dataschema, invalid_utf8)
          ] do
        assert {:error, _message} = Signal.new(attributes)
      end

      assert {:error, _message} = Signal.new(Keyword.put(base, :source, "/bad%ZZ"))
      assert {:error, _message} = Signal.new(Keyword.put(base, :source, "/café"))

      assert {:error, _message} =
               Signal.new(Keyword.put(base, :dataschema, "https://example.com/bad%ZZ"))

      assert {:error, _message} =
               Signal.new(Keyword.put(base, :datacontenttype, "not a media type"))

      assert {:error, _message} =
               Signal.new(Keyword.put(base, :datacontenttype, "text/plain\r\nx-header: value"))
    end

    test "accepts valid media type parameters" do
      assert {:ok, signal} =
               Signal.new(
                 type: "example.event",
                 source: "/example",
                 datacontenttype: "application/json; charset=utf-8"
               )

      assert signal.datacontenttype == "application/json; charset=utf-8"

      assert {:ok, _signal} =
               Signal.new(
                 type: "example.event",
                 source: "/example",
                 datacontenttype: ~s(application/json; profile="https://example.com/profile")
               )
    end

    test "keeps validator callbacks total for direct use" do
      assert {:error, _message} = Signal.validate_uri_reference(:invalid, [])
      assert {:error, _message} = Signal.validate_uri_reference("http://[", [])
      assert {:error, _message} = Signal.validate_absolute_uri(:invalid, [])
      assert {:error, _message} = Signal.validate_rfc3339(:invalid, [])
      assert {:error, _message} = Signal.validate_utf8_string(:invalid, [])
      assert {:error, _message} = Signal.validate_media_type(:invalid, [])
    end
  end

  describe "new/3" do
    test "creates a Signal with explicit type and data" do
      assert {:ok, signal} =
               Signal.new("user.created", %{user_id: "123"}, source: "/accounts")

      assert signal.type == "user.created"
      assert signal.data == %{user_id: "123"}
      assert signal.source == "/accounts"
    end

    test "requires source in the attribute set" do
      assert {:error, error} = Signal.new("user.created", %{user_id: "123"})
      assert error =~ "source"
    end

    test "rejects type and data overrides" do
      assert {:error, error} = Signal.new("test.event", %{}, type: "other.event")
      assert error =~ "attribute \"type\""

      assert {:error, error} = Signal.new("test.event", %{}, %{"data" => "other"})
      assert error =~ "attribute \"data\""
    end

    test "accepts all data values, including an empty string" do
      for value <- [nil, "", "text", 1, true, [1, 2], %{value: 1}] do
        assert {:ok, signal} = Signal.new("test.event", value, source: "/test")
        assert signal.data == value
      end
    end

    test "rejects malformed option containers without raising" do
      assert {:error, _message} = Signal.new([:bad])
      assert {:error, _message} = Signal.new("test.event", %{}, [:bad])
      assert {:error, _message} = Signal.new(%{{:tuple, :key} => 1})
    end
  end
end
