defmodule Jido.Agent.CodecTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Agent.Extension.Declaration, as: ExtensionDeclaration
  alias Jido.Agent.Plugin
  alias Jido.Agent.PluginDefaults
  alias Jido.Agent.Registry
  alias Jido.Agent.Schedule

  defmodule CodecAction do
    use Jido.Action, name: "codec_action", schema: []

    @impl true
    def run(params, _context) do
      Process.put(:codec_action_ran, true)
      {:ok, params}
    end
  end

  defmodule CodecPlugin do
    use Jido.Plugin,
      name: "codec_plugin",
      state_key: :codec_plugin,
      actions: [CodecAction]

    @impl true
    def mount(_agent, _config) do
      Process.put(:codec_plugin_mounted, true)
      {:ok, %{}}
    end
  end

  defmodule CodecExtension do
    @behaviour Jido.Agent.Extension

    @impl true
    def validate_executable(_data), do: :ok

    @impl true
    def compile(_data, _context) do
      Process.put(:codec_extension_compiled, true)
      {:ok, %{}}
    end

    @impl true
    def encode(%{enabled: enabled, mode: mode}, %Registry{}) do
      Process.put(:codec_extension_encoded, true)
      {:ok, %{"enabled" => enabled, "mode" => Atom.to_string(mode)}}
    end

    @impl true
    def decode(%{"enabled" => enabled, "mode" => "ready"}, %Registry{}) do
      Process.put(:codec_extension_decoded, true)
      {:ok, %{enabled: enabled, mode: :ready}}
    end
  end

  defmodule RouteMatches do
    def selected?(_signal), do: true
  end

  setup do
    Process.delete(:codec_action_ran)
    Process.delete(:codec_plugin_mounted)
    Process.delete(:codec_extension_compiled)
    Process.delete(:codec_extension_encoded)
    Process.delete(:codec_extension_decoded)
    :ok
  end

  test "encodes and decodes a neutral Agent definition" do
    agent = Agent.new!(name: "stored_agent", plugin_defaults: :none)

    assert {:ok, document, registry} = Codec.encode(agent)
    assert document["type"] == "jido.agent"
    assert document["version"] == 1
    assert {:ok, ^agent} = Codec.decode(document, registry)
  end

  test "encode/2 requires a Registry" do
    agent = Agent.new!(name: "stored_agent")

    assert {:error, %Jido.Error.ValidationError{}} = Codec.encode(agent, :invalid)
    assert {:error, %Jido.Error.Invalid{errors: [_error]}} = Codec.diagnose(%{}, :invalid)
    assert {:ok, %Registry{}} = Registry.from_agent(agent)
  end

  test "real JSON bytes preserve the exact full definition and re-encode" do
    {agent, registry} = full_fixture()

    assert {:ok, document} = Codec.encode(agent, registry)

    assert Map.keys(document) |> Enum.sort() ==
             ~w(description extensions metadata name plugin_defaults plugins routes schedules state_schema type version)

    refute Map.has_key?(document, "id")
    refute Map.has_key?(document, "state")
    refute Map.has_key?(document, "agent_module")
    refute Map.has_key?(document, "strategy")
    refute Map.has_key?(document, "category")
    refute Map.has_key?(document, "tags")
    refute Map.has_key?(document, "vsn")

    decoded_document = document |> Jason.encode!() |> Jason.decode!()

    assert {:ok, decoded} = Codec.decode(decoded_document, registry)
    assert decoded == agent
    assert {:ok, ^document} = Codec.encode(decoded, registry)
    assert {:ok, ^agent} = Codec.diagnose(decoded_document, registry)

    assert Enum.map(decoded.plugins, & &1.module) == [CodecPlugin, CodecPlugin]
    assert Enum.map(decoded.routes, & &1.path) == ["codec.selected", "codec.tick"]
    assert Enum.map(decoded.schedules, & &1.name) == ["tick", "later"]
    assert Enum.map(decoded.extensions, & &1.module) == [CodecExtension]
  end

  test "generic Maps preserve string, integer, atom, and named MFA values" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)

    assert %{"$type" => "map", "entries" => entries} = document["metadata"]
    assert is_list(entries)

    assert {:ok, decoded} =
             document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)

    assert decoded.metadata == agent.metadata
    assert decoded.metadata[:callback] == {RouteMatches, :selected?, [:ready]}
    assert decoded.metadata[7][:atom_key] == :ready
    assert decoded.metadata["string-key"] == "value"
  end

  test "rejects instances with one definition-only error" do
    {agent, registry} = full_fixture()
    instance = %{agent | id: "instance", state: %{}, agent_module: __MODULE__}

    assert {:error, error} = Codec.encode(instance, registry)
    assert Exception.message(error) == "Agent Codec accepts definition-only values"
    assert error.details.fields == [:id, :state, :agent_module]
  end

  test "root records reject runtime, strategy, and all unknown fields" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)

    invalid =
      document
      |> Map.put("id", "instance")
      |> Map.put("state", %{})
      |> Map.put("agent_module", "Elixir.Bad")
      |> Map.put("strategy", "Elixir.Bad")
      |> Map.put("category", "bad")

    assert {:error, %Jido.Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) ==
             [["agent_module"], ["category"], ["id"], ["state"], ["strategy"]]

    assert {:error, first} = Codec.decode(invalid, registry)
    assert first.details.path == ["agent_module"]
  end

  test "uses exact Registry kinds for every executable declaration" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)

    [route | routes] = document["routes"]
    invalid = %{document | "routes" => [%{route | "action" => "plugins/main"} | routes]}

    assert {:error, error} = Codec.decode(invalid, registry)
    assert Exception.message(error) == "Agent Registry identifier has the wrong entry kind"
    assert error.details.path == ["routes", 0, "action"]

    [extension] = document["extensions"]
    invalid = %{document | "extensions" => [%{extension | "module" => "plugins/main"}]}

    assert {:error, error} = Codec.decode(invalid, registry)
    assert error.details.path == ["extensions", 0, "module"]
  end

  test "schema resolution is revalidated by the canonical Agent constructor" do
    agent = Agent.new!(name: "schema_agent", state_schema: [])

    registry =
      Registry.new!(%{
        "schemas/good" => {:schema, []},
        "schemas/bad" => {:schema, fn -> :not_static end}
      })

    assert {:ok, document} = Codec.encode(agent, registry)
    invalid = %{document | "state_schema" => "schemas/bad"}

    assert {:error, error} = Codec.decode(invalid, registry)
    assert Exception.message(error) =~ "state_schema must be static module data"
    assert error.details.path == ["state_schema"]
  end

  test "nested declaration records are closed" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)

    [plugin | plugins] = document["plugins"]
    [route | routes] = document["routes"]
    [schedule | schedules] = document["schedules"]
    [extension] = document["extensions"]

    invalid = %{
      document
      | "plugin_defaults" => Map.put(document["plugin_defaults"], "runtime", true),
        "plugins" => [Map.put(plugin, "runtime", true) | plugins],
        "routes" => [Map.put(route, "runtime", true) | routes],
        "schedules" => [Map.put(schedule, "job_id", "derived") | schedules],
        "extensions" => [Map.put(extension, "codec", true)]
    }

    assert {:error, %Jido.Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) == [
             ["plugin_defaults", "runtime"],
             ["plugins", 0, "runtime"],
             ["routes", 0, "runtime"],
             ["schedules", 0, "job_id"],
             ["extensions", 0, "codec"]
           ]
  end

  test "duplicate decoded tagged-Map keys fail" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)

    duplicate = %{
      "$type" => "map",
      "entries" => [
        %{"key" => "same", "value" => 1},
        %{"key" => "same", "value" => 2}
      ]
    }

    assert {:error, error} = Codec.decode(%{document | "metadata" => duplicate}, registry)
    assert Exception.message(error) == "stored Agent map contains a duplicate key"
    assert error.details.path == ["metadata", "entries", 1, "key"]
  end

  test "invalid UTF-8 fails on encode and decode" do
    invalid = <<255>>
    agent = Agent.new!(name: "utf8_agent")
    registry = Registry.new!(%{"schemas/state" => {:schema, []}})

    assert {:error, _error} = Codec.encode(%{agent | metadata: %{"bad" => invalid}}, registry)
    assert {:ok, document} = Codec.encode(agent, registry)

    assert {:error, error} = Codec.decode(%{document | "description" => invalid}, registry)
    assert Exception.message(error) == "stored Agent strings must be valid UTF-8"
  end

  test "envelope and document limits are terminal" do
    agent = Agent.new!(name: "limit_agent")
    registry = Registry.new!(%{"schemas/state" => {:schema, []}})
    assert {:ok, document} = Codec.encode(agent, registry)

    invalid_envelope = %{document | "version" => 2}

    assert {:error, %Jido.Error.Invalid{errors: [version_error]}} =
             Codec.diagnose(invalid_envelope, registry)

    assert version_error.details.path == ["version"]

    deep = Enum.reduce(1..101, 0, fn _index, value -> [value] end)
    wide = List.duplicate(0, 10_001)
    many = List.duplicate(List.duplicate(0, 10_000), 11)

    for {value, message} <- [
          {deep, "stored Agent exceeds its nesting limit"},
          {wide, "stored Agent collection exceeds its size limit"},
          {many, "stored Agent exceeds its total node limit"}
        ] do
      assert {:error, error} = Codec.decode(%{document | "metadata" => value}, registry)
      assert Exception.message(error) == message
    end
  end

  test "diagnose returns ordered independent errors and decode returns only the first" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)
    [plugin | plugins] = document["plugins"]
    [route | routes] = document["routes"]
    [schedule | schedules] = document["schedules"]

    invalid = %{
      document
      | "plugins" => [%{plugin | "module" => 42, "as" => 42} | plugins],
        "routes" => [%{route | "action" => 42, "match" => 42} | routes],
        "schedules" => [%{schedule | "name" => 42, "data" => true} | schedules]
    }

    assert {:error, %Jido.Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry)

    assert Enum.map(errors, & &1.details.path) == [
             ["plugins", 0, "module"],
             ["plugins", 0, "as"],
             ["routes", 0, "action"],
             ["routes", 0, "match"],
             ["schedules", 0, "name"],
             ["schedules", 0, "data"]
           ]

    assert {:error, first} = Codec.decode(invalid, registry)
    assert first.message == hd(errors).message
    assert first.details == hd(errors).details
    refute match?({:ok, %Agent{}}, Codec.decode(invalid, registry))
  end

  test "codec work is inert" do
    {agent, registry} = full_fixture()
    assert {:ok, document} = Codec.encode(agent, registry)
    assert {:ok, ^agent} = Codec.decode(document, registry)

    refute Process.get(:codec_action_ran)
    refute Process.get(:codec_plugin_mounted)
    refute Process.get(:codec_extension_compiled)
    assert Process.get(:codec_extension_encoded)
    assert Process.get(:codec_extension_decoded)
  end

  defp full_fixture do
    schema = Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})

    plugin =
      Plugin.new!(
        module: CodecPlugin,
        as: :search,
        config: %{limit: 10, mode: :ready},
        metadata: %{owner: "codec"}
      )

    defaults =
      PluginDefaults.new!(
        mode: :none,
        overrides: %{search: plugin, removed: :disabled}
      )

    agent =
      Agent.new!(
        name: "full_codec_agent",
        description: "Stored definition",
        state_schema: schema,
        plugin_defaults: defaults,
        plugins: [plugin, Plugin.new!(module: CodecPlugin, as: :second)],
        routes: [
          {"codec.selected", &RouteMatches.selected?/1, CodecAction,
           %{"limit" => 3, source: :codec}, 10},
          {"codec.tick", CodecAction}
        ],
        schedules: [
          Schedule.new!(
            name: "tick",
            cron_expression: "*/5 * * * *",
            signal_type: "codec.tick",
            data: %{kind: :ready},
            metadata: %{owner: "codec"}
          ),
          Schedule.new!(
            name: "later",
            cron_expression: "0 * * * *",
            signal_type: "codec.later",
            data: %{},
            metadata: %{}
          )
        ],
        extensions: [
          ExtensionDeclaration.new!(
            module: CodecExtension,
            data: %{enabled: true, mode: :ready},
            metadata: %{owner: :codec}
          )
        ],
        metadata: %{
          "string-key" => "value",
          7 => %{atom_key: :ready},
          callback: {RouteMatches, :selected?, [:ready]}
        }
      )

    registry =
      Registry.new!(%{
        "schemas/state" => {:schema, schema},
        "plugins/main" => {:plugin, CodecPlugin},
        "actions/run" => {:action, CodecAction},
        "route-matches/selected" => {:route_match, &RouteMatches.selected?/1},
        "extensions/main" => {:extension, CodecExtension},
        "atoms/search" => {:atom, :search},
        "atoms/removed" => {:atom, :removed},
        "atoms/second" => {:atom, :second},
        "atoms/limit" => {:atom, :limit},
        "atoms/mode" => {:atom, :mode},
        "atoms/ready" => {:atom, :ready},
        "atoms/owner" => {:atom, :owner},
        "atoms/source" => {:atom, :source},
        "atoms/kind" => {:atom, :kind},
        "atoms/enabled" => {:atom, :enabled},
        "atoms/codec" => {:atom, :codec},
        "atoms/atom-key" => {:atom, :atom_key},
        "atoms/callback" => {:atom, :callback},
        "atoms/route-matches" => {:atom, RouteMatches},
        "atoms/selected" => {:atom, :selected?}
      })

    {agent, registry}
  end
end
