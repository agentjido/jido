defmodule Jido.Signal.SanitizerTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Sanitizer

  defmodule DetailError do
    defexception [:message, :code]
  end

  defmodule ScalarStruct do
    defstruct [:id, :status, :payload]
  end

  defmodule NestedStruct do
    defstruct payload: %{}
  end

  defmodule SensitiveStruct do
    defstruct [:token]
  end

  describe "sanitize/2" do
    test "uses map fields for malformed struct-valued Signal extensions" do
      secret = "extension-struct-secret-47ca"
      original = Signal.new!("test.event", %{}, source: "/test")

      for extensions <- [%URI{query: secret}, MapSet.new([{:token, secret}])] do
        signal = %{original | extensions: extensions}

        for profile <- [:telemetry, :transport] do
          sanitized = Sanitizer.sanitize(signal, profile)
          id_key = if profile == :telemetry, do: :id, else: "id"
          names_key = if profile == :telemetry, do: :extensions, else: "extensions"
          assert sanitized[id_key] == original.id
          assert "__struct__" in sanitized[names_key]
          refute inspect(sanitized) =~ secret
          refute Sanitizer.preview(signal, profile) =~ secret
        end

        public =
          Jido.Signal.Error.validation_error("invalid", %{signal: signal})
          |> Jido.Signal.Error.to_map()

        assert public.type == :invalid_input_error
        assert public.details["signal"]["id"] == original.id
        refute Jason.encode!(public) =~ secret
      end
    end

    test "bounds custom struct and exception module names" do
      for value <- JidoSignalTest.Fixtures.Diagnostics.values(),
          {profile, limit} <- [telemetry: 160, transport: 1024] do
        key = if is_exception(value), do: :module, else: :__struct__
        key = if profile == :transport, do: Atom.to_string(key), else: key
        name = Sanitizer.sanitize(value, profile)[key]
        assert byte_size(name) <= limit + 3
        assert String.valid?(name)

        if profile == :telemetry do
          assert name == String.slice(inspect(value.__struct__), 0, 160) <> "..."
        else
          assert name == inspect(value.__struct__)
        end
      end
    end

    test "redacts secrets in compound map keys at all boundaries" do
      secret = "compound-key-secret-83f2"

      keys = [
        {:password, secret},
        %{password: secret},
        [{:token, secret}],
        %ScalarStruct{payload: :safe, id: %{secret: secret}},
        %SensitiveStruct{token: secret},
        DetailError.exception(message: secret, code: %{token: secret}),
        [{:password, secret} | :tail],
        %{%{token: secret} => :safe}
      ]

      for profile <- [:telemetry, :transport], key <- keys do
        value = %{key => :safe}
        refute inspect(Sanitizer.sanitize(value, profile)) =~ secret
        refute Sanitizer.preview(value, profile, max_length: 10_000) =~ secret

        refute inspect(
                 Jido.Signal.Error.to_map(Jido.Signal.Error.validation_error("invalid", value))
               ) =~ secret
      end
    end

    test "bounds Signal fields and nested Signal data" do
      large = String.duplicate("s", 100_000)

      signal =
        Signal.new!(%{
          id: large,
          type: large,
          source: large,
          subject: large,
          datacontenttype: "text/" <> large
        })

      for {profile, limit} <- [telemetry: 160, transport: 1024] do
        sanitized = Sanitizer.sanitize(signal, profile)

        for field <- [:id, :type, :source, :subject, :datacontenttype] do
          key = if profile == :telemetry, do: field, else: Atom.to_string(field)
          assert byte_size(Map.fetch!(sanitized, key)) <= limit + 3
        end
      end

      nested =
        Enum.reduce(1..30, :leaf, fn _, data -> Signal.new!("nested", data, source: "/test") end)

      sanitized = Sanitizer.sanitize(nested, :transport)
      refute inspect(sanitized, limit: :infinity) =~ "leaf"
      assert byte_size(:erlang.term_to_binary(sanitized)) < 3_000
      error = Jido.Signal.Error.validation_error("invalid", %{signal: nested})
      assert byte_size(Jason.encode!(Jido.Signal.Error.to_map(error))) < 3_000
    end

    test "redacts sensitive keys for telemetry" do
      sanitized =
        Sanitizer.sanitize(
          %{
            password: "super-secret",
            nested: %{token: "abc123"},
            safe: "value"
          },
          :telemetry
        )

      assert sanitized.password == "[REDACTED]"
      assert sanitized.nested.token == "[REDACTED]"
      assert sanitized.safe == "value"
    end

    test "redacts sensitive header tuple lists" do
      sanitized =
        Sanitizer.sanitize(
          [
            {"x-api-key", "api-secret"},
            {"authorization", "Bearer secret-token"},
            {"x-custom", "visible"}
          ],
          :telemetry
        )

      assert sanitized["x-api-key"] == "[REDACTED]"
      assert sanitized["authorization"] == "[REDACTED]"
      assert sanitized["x-custom"] == "visible"
    end

    test "redacts sensitive pairs inside mixed lists" do
      value = [{:password, "mixed-secret"}, :tail]

      assert [{:password, "[REDACTED]"}, :tail] =
               Sanitizer.sanitize(value, :telemetry)

      assert [
               %{
                 "__type__" => "tuple",
                 "items" => ["password", "[REDACTED]"]
               },
               "tail"
             ] = Sanitizer.sanitize(value, :transport)
    end

    test "keeps empty lists as lists" do
      assert Sanitizer.sanitize([], :telemetry) == []
      assert Sanitizer.sanitize([], :transport) == []
    end

    test "serializes tuples and structs for transport" do
      {:ok, signal} =
        Signal.new(%{
          type: "user.created",
          source: "/auth",
          data: %{name: "Ada", password: "hidden"}
        })

      sanitized = Sanitizer.sanitize(%{signal: signal, value: {:ok, :accepted}}, :transport)

      assert sanitized["signal"]["__struct__"] == "Jido.Signal"
      assert sanitized["signal"]["data"]["password"] == "[REDACTED]"
      assert sanitized["value"] == %{"__type__" => "tuple", "items" => ["ok", "accepted"]}
    end

    test "removes URI credentials and query data" do
      uri = URI.parse("https://user:pass@example.com/path?token=secret#private")

      assert Sanitizer.sanitize(uri, :telemetry) == "https://example.com/path"
    end

    test "bounds URI and runtime value text" do
      uri = URI.parse("https://user:secret@example.com/" <> String.duplicate("p", 100_000))
      bits = <<0::10_001>>
      {:ok, date} = Date.new(Integer.pow(10, 2048), 1, 1)
      {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])
      {:ok, datetime} = DateTime.new(date, ~T[00:00:00])

      for {profile, limit} <- [telemetry: 160, transport: 1024] do
        sanitized_uri = Sanitizer.sanitize(uri, profile)
        assert byte_size(sanitized_uri) <= limit + 3
        refute sanitized_uri =~ "secret"
        sanitized_bits = Sanitizer.sanitize(bits, profile)
        text = if profile == :telemetry, do: sanitized_bits, else: sanitized_bits["value"]
        assert byte_size(text) <= limit + 3

        for temporal <- [date, naive, datetime] do
          assert byte_size(Sanitizer.sanitize(temporal, profile)) <= limit + 3
        end
      end
    end

    test "does not include exception messages" do
      sanitized = Sanitizer.sanitize(RuntimeError.exception("token=secret"), :telemetry)

      assert sanitized == %{module: "RuntimeError"}
      refute inspect(sanitized) =~ "secret"
    end

    test "keeps truncated transport text as valid UTF-8" do
      sanitized = Sanitizer.sanitize(String.duplicate("€", 600), :transport)

      assert String.valid?(sanitized)
      assert byte_size(sanitized) <= 1_027
    end

    test "bounds nested tuples" do
      nested = Enum.reduce(1..20, :value, fn _number, acc -> {acc} end)
      sanitized = Sanitizer.sanitize(nested, :telemetry)

      assert inspect(sanitized) =~ "summary"
      assert byte_size(:erlang.term_to_binary(sanitized)) < 1_000
    end

    test "uses boundary-safe scalar and binary values" do
      assert Sanitizer.sanitize(:accepted, :telemetry) == :accepted
      assert Sanitizer.sanitize(:accepted, :transport) == "accepted"
      assert Sanitizer.sanitize(nil, :transport) == nil
      assert Sanitizer.sanitize(12.5, :telemetry) == 12.5

      invalid_binary = <<255, 0, 1>>

      assert %{__type__: :binary, bytes: 3, preview: preview} =
               Sanitizer.sanitize(invalid_binary, :telemetry)

      assert is_binary(preview)

      assert %{"__type__" => "binary", "bytes" => 3} =
               Sanitizer.sanitize(invalid_binary, :transport)
    end

    test "formats date and time values" do
      assert Sanitizer.sanitize(~D[2026-08-26], :transport) == "2026-08-26"
      assert Sanitizer.sanitize(~T[12:30:01], :telemetry) == "12:30:01"

      assert Sanitizer.sanitize(~N[2026-08-26 12:30:01], :transport) ==
               "2026-08-26T12:30:01"

      assert Sanitizer.sanitize(~U[2026-08-26 12:30:01Z], :telemetry) ==
               "2026-08-26T12:30:01Z"
    end

    test "keeps only safe Signal fields in telemetry" do
      signal =
        Signal.new!("user.created", %{password: "hidden"},
          source: "/users",
          subject: "user-1"
        )

      assert %{type: "user.created", source: "/users", subject: "user-1"} =
               Sanitizer.sanitize(signal, :telemetry)

      refute Map.has_key?(Sanitizer.sanitize(signal, :telemetry), :data)
    end

    test "sanitizes exception fields and general structs" do
      assert %{module: module, details: %{code: 42}} =
               Sanitizer.sanitize(DetailError.exception(message: "secret", code: 42), :telemetry)

      assert module =~ "DetailError"

      assert %{"__struct__" => struct_module, "id" => "one", "status" => "ready"} =
               Sanitizer.sanitize(
                 %ScalarStruct{id: "one", status: :ready, payload: %{secret: "hidden"}},
                 :transport
               )

      assert struct_module =~ "ScalarStruct"

      assert %{__struct__: nested_module, summary: %{summary: :list, count: 1}} =
               Sanitizer.sanitize(%NestedStruct{}, :telemetry)

      assert nested_module =~ "NestedStruct"
    end

    test "bounds maps and lists with profile-specific markers" do
      telemetry_map = Map.new(1..12, &{"key-#{&1}", &1})
      sanitized_map = Sanitizer.sanitize(telemetry_map, :telemetry)
      assert sanitized_map.__truncated__ == %{count: 12}

      transport_map = Map.new(1..52, &{"key-#{&1}", &1})

      assert %{"__truncated__" => %{"count" => 52}} =
               Sanitizer.sanitize(transport_map, :transport)

      telemetry_list = Sanitizer.sanitize(Enum.to_list(1..12), :telemetry)
      assert List.last(telemetry_list) == "... (2 more)"

      transport_list = Sanitizer.sanitize(Enum.to_list(1..52), :transport)
      assert List.last(transport_list) == %{"__truncated__" => %{"count" => 52}}
    end

    test "summarizes deep maps and lists" do
      nested_map = %{one: %{two: %{three: %{four: :value}}}}

      assert %{one: %{two: %{three: %{summary: :map, size: 1}}}} =
               Sanitizer.sanitize(nested_map, :telemetry)

      nested_list = [[[[[[[:value]]]]]]]

      assert [[[[[[%{"summary" => "list", "count" => 1}]]]]]] =
               Sanitizer.sanitize(nested_list, :transport)
    end

    test "normalizes map keys and opaque runtime values" do
      reference = make_ref()
      function = fn -> :ok end
      bitstring = <<1::1>>

      sanitized =
        Sanitizer.sanitize(
          %{{:tuple, :key} => reference, "x-token" => "hidden", function: function},
          :transport
        )

      assert sanitized["x-token"] == "[REDACTED]"
      assert sanitized["{:tuple, :key}"]["__type__"] == "reference"
      assert sanitized["function"]["__type__"] == "function"
      assert Sanitizer.sanitize(bitstring, :transport)["__type__"] == "bitstring"
      assert is_binary(Sanitizer.sanitize(self(), :telemetry))
    end

    test "handles improper lists without raising" do
      improper = [1, [2 | 3] | 4]

      assert %{__type__: :improper_list} = sanitized = Sanitizer.sanitize(improper, :telemetry)
      refute Map.has_key?(sanitized, :preview)

      assert %{"__type__" => "improper_list"} =
               sanitized =
               Sanitizer.sanitize(%{nested: improper}, :transport)["nested"]

      refute Map.has_key?(sanitized, "preview")
    end

    test "does not expose sensitive values in improper lists" do
      improper = [{:token, "improper-secret"} | :tail]

      for profile <- [:telemetry, :transport] do
        sanitized = Sanitizer.sanitize(improper, profile)
        refute inspect(sanitized) =~ "improper-secret"
      end
    end

    test "bounds large keys, invalid binaries, and maps" do
      large_key = String.duplicate("k", 100_000)
      invalid_binary = :binary.copy(<<255>>, 1_000_000)
      large_map = Map.new(1..100_000, &{"key-#{&1}", &1})
      large_composite_key = {:key, Enum.to_list(1..100_000)}

      sanitized_key_map = Sanitizer.sanitize(%{large_key => "value"}, :telemetry)
      [sanitized_key] = Map.keys(sanitized_key_map)
      assert byte_size(sanitized_key) <= 163

      sanitized_composite_map =
        Sanitizer.sanitize(%{large_composite_key => "value"}, :transport)

      [sanitized_composite_key] = Map.keys(sanitized_composite_map)
      assert byte_size(sanitized_composite_key) <= 1_027

      assert %{bytes: 1_000_000, preview: preview} =
               Sanitizer.sanitize(invalid_binary, :telemetry)

      assert byte_size(preview) <= 163

      assert %{__truncated__: %{count: 100_000}} =
               Sanitizer.sanitize(large_map, :telemetry)
    end
  end

  describe "preview/3" do
    test "returns a bounded inspect-safe preview" do
      preview =
        Sanitizer.preview(%{payload: String.duplicate("a", 400)}, :telemetry, max_length: 60)

      assert String.length(preview) <= 63
      assert String.ends_with?(preview, "...")
    end

    test "uses the default limit when the requested limit is invalid" do
      assert is_binary(Sanitizer.preview(%{value: 1}, :telemetry, max_length: -1))
    end

    test "supports the transport default and a zero limit" do
      assert is_binary(Sanitizer.preview(%{value: 1}, :transport))
      assert Sanitizer.preview(%{value: 1}, :telemetry, max_length: 0) == "..."
    end
  end
end
