defmodule JidoExampleTest.IdentityPluginTest do
  @moduledoc """
  Example test demonstrating Identity as a default plugin and capability routing patterns.

  This test shows:
  - Every agent gets `Jido.Identity.Plugin` automatically (default singleton plugin)
  - Using `Jido.Identity.Agent` helpers: `ensure/2`, `age/1`, capability queries/mutations
  - Extension management for plugin-owned identity data
  - Snapshot for sharing identity with other agents
  - Evolving identity over simulated time via `Jido.Identity.evolve/2` and the Evolve action
  - Replacing the default Identity.Plugin with a custom implementation
  - Disabling the identity plugin with `default_plugins: %{__identity__: false}`

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Identity
  alias Jido.Identity.Agent, as: IdentityAgent
  alias Jido.AgentServer

  # ===========================================================================
  # ACTIONS
  # ===========================================================================

  defmodule RegisterCapabilitiesAction do
    @moduledoc false
    use Jido.Action,
      name: "register_capabilities",
      schema: [
        actions: [type: {:list, :string}, default: []],
        tags: [type: {:list, :atom}, default: []]
      ]

    def run(%{actions: actions, tags: tags}, ctx) do
      identity =
        case ctx.state[:__identity__] do
          nil -> Identity.new()
          existing -> existing
        end

      identity =
        Enum.reduce(actions, identity, fn action_id, acc ->
          current = acc.capabilities[:actions] || []

          if action_id in current do
            acc
          else
            %{acc | capabilities: Map.put(acc.capabilities, :actions, current ++ [action_id])}
          end
        end)

      identity =
        Enum.reduce(tags, identity, fn tag, acc ->
          current = acc.capabilities[:tags] || []

          if tag in current do
            acc
          else
            %{acc | capabilities: Map.put(acc.capabilities, :tags, current ++ [tag])}
          end
        end)

      updated = %{identity | rev: identity.rev + 1, updated_at: System.system_time(:millisecond)}
      {:ok, %{__identity__: updated}}
    end
  end

  defmodule QueryCapabilitiesAction do
    @moduledoc false
    use Jido.Action,
      name: "query_capabilities",
      schema: []

    def run(_params, ctx) do
      identity = ctx.state[:__identity__]

      case identity do
        nil ->
          {:ok, %{has_identity: false, action_count: 0, tags: []}}

        %Identity{} ->
          {:ok,
           %{
             has_identity: true,
             action_count: length(identity.capabilities[:actions] || []),
             tags: identity.capabilities[:tags] || []
           }}
      end
    end
  end

  # ===========================================================================
  # CUSTOM IDENTITY PLUGIN
  # ===========================================================================

  defmodule CustomIdentityPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "custom_identity",
      state_key: :__identity__,
      actions: [],
      description: "Custom identity plugin that auto-initializes with config."

    @impl Jido.Plugin
    def mount(_agent, config) do
      profile = Map.get(config, :profile, %{age: 0, origin: :configured})
      tags = Map.get(config, :tags, [])

      identity =
        Identity.new(
          profile: profile,
          capabilities: %{actions: [], tags: tags, io: %{}, limits: %{}}
        )

      {:ok, identity}
    end
  end

  # ===========================================================================
  # AGENTS
  # ===========================================================================

  defmodule WebCrawlerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "web_crawler",
      description: "Agent with identity for capability-based routing",
      schema: [
        has_identity: [type: :boolean, default: false],
        action_count: [type: :integer, default: 0],
        tags: [type: {:list, :atom}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"register_capabilities", RegisterCapabilitiesAction},
        {"query_capabilities", QueryCapabilitiesAction},
        {"evolve", Jido.Identity.Actions.Evolve}
      ]
    end
  end

  defmodule PreConfiguredAgent do
    @moduledoc false
    use Jido.Agent,
      name: "pre_configured",
      description: "Agent with custom identity plugin that auto-initializes",
      default_plugins: %{
        __identity__:
          {CustomIdentityPlugin, %{profile: %{age: 5, origin: :spawned}, tags: [:web]}}
      },
      schema: [
        status: [type: :atom, default: :idle]
      ]
  end

  defmodule NoIdentityAgent do
    @moduledoc false
    use Jido.Agent,
      name: "no_identity",
      description: "Agent with identity plugin disabled",
      default_plugins: %{__identity__: false},
      schema: [
        value: [type: :integer, default: 0]
      ]
  end

  # ===========================================================================
  # TESTS: Default identity plugin
  # ===========================================================================

  describe "identity plugin is a default singleton" do
    test "new agent has no identity until initialized on demand" do
      agent = WebCrawlerAgent.new()

      refute IdentityAgent.has_identity?(agent)
    end

    test "IdentityAgent.ensure initializes identity on demand" do
      agent = WebCrawlerAgent.new()

      agent =
        IdentityAgent.ensure(agent,
          profile: %{age: 0, origin: :configured},
          capabilities: %{
            actions: ["FetchURL", "ParseHTML"],
            tags: [:web, :parsing],
            io: %{network?: true},
            limits: %{max_concurrency: 4}
          }
        )

      assert IdentityAgent.has_identity?(agent)
      assert IdentityAgent.age(agent) == 0
      assert IdentityAgent.supports_action?(agent, "FetchURL")
      assert IdentityAgent.has_tag?(agent, :web)
    end
  end

  describe "capability management with helpers" do
    test "add and query actions" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_action("ParseHTML")
        |> IdentityAgent.add_action("ExtractLinks")

      assert IdentityAgent.supports_action?(agent, "FetchURL")
      assert IdentityAgent.supports_action?(agent, "ParseHTML")
      assert IdentityAgent.supports_action?(agent, "ExtractLinks")
      refute IdentityAgent.supports_action?(agent, "SendEmail")
      assert length(IdentityAgent.actions(agent)) == 3
    end

    test "add and query tags" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.add_tag(:web)
        |> IdentityAgent.add_tag(:parsing)

      assert IdentityAgent.has_tag?(agent, :web)
      assert IdentityAgent.has_tag?(agent, :parsing)
      refute IdentityAgent.has_tag?(agent, :analysis)
      assert IdentityAgent.tags(agent) == [:web, :parsing]
    end

    test "set limits and io flags" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.set_limit(:max_concurrency, 4)
        |> IdentityAgent.set_limit(:max_runtime_ms, 30_000)
        |> IdentityAgent.set_io(:network?, true)
        |> IdentityAgent.set_io(:filesystem?, false)

      caps = IdentityAgent.capabilities(agent)
      assert caps[:limits][:max_concurrency] == 4
      assert caps[:limits][:max_runtime_ms] == 30_000
      assert caps[:io][:network?] == true
      assert caps[:io][:filesystem?] == false
    end

    test "remove action" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_action("ParseHTML")
        |> IdentityAgent.remove_action("FetchURL")

      refute IdentityAgent.supports_action?(agent, "FetchURL")
      assert IdentityAgent.supports_action?(agent, "ParseHTML")
    end

    test "no duplicate actions or tags" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_tag(:web)
        |> IdentityAgent.add_tag(:web)

      assert length(IdentityAgent.actions(agent)) == 1
      assert length(IdentityAgent.tags(agent)) == 1
    end
  end

  describe "extension management" do
    test "plugins store identity extensions in their namespace" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.put_extension("character", %{
          persona: %{traits: [%{name: "analytical", intensity: 0.9}]},
          voice: %{tone: :professional},
          __public__: %{persona: %{role: "Data analyst"}, voice: %{tone: :professional}}
        })
        |> IdentityAgent.put_extension("safety", %{
          guidelines: ["Never provide medical advice"],
          __public__: %{}
        })

      character_ext = IdentityAgent.get_extension(agent, "character")
      assert character_ext.persona.traits == [%{name: "analytical", intensity: 0.9}]
      assert character_ext.voice.tone == :professional

      safety_ext = IdentityAgent.get_extension(agent, "safety")
      assert "Never provide medical advice" in safety_ext.guidelines
    end

    test "merge_extension shallow merges into existing extension" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.put_extension("character", %{voice: %{tone: :casual}, level: 1})
        |> IdentityAgent.merge_extension("character", %{level: 2, style: :bold})

      ext = IdentityAgent.get_extension(agent, "character")
      assert ext.voice == %{tone: :casual}
      assert ext.level == 2
      assert ext.style == :bold
    end

    test "update_extension applies function to extension" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure()
        |> IdentityAgent.put_extension("character", %{level: 1})
        |> IdentityAgent.update_extension("character", fn ext ->
          Map.update!(ext, :level, &(&1 + 1))
        end)

      assert IdentityAgent.get_extension(agent, "character").level == 2
    end
  end

  describe "snapshot for sharing identity" do
    test "snapshot includes capabilities and public extensions only" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure(profile: %{age: 3, generation: 2, origin: :spawned})
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_tag(:web)
        |> IdentityAgent.put_extension("character", %{
          persona: %{traits: [%{name: "analytical", intensity: 0.9}]},
          secret_key: "should-not-appear",
          __public__: %{persona: %{role: "Data analyst"}}
        })
        |> IdentityAgent.put_extension("internal", %{
          data: "no public key, excluded from snapshot"
        })

      snapshot = IdentityAgent.snapshot(agent)

      assert "FetchURL" in snapshot.capabilities[:actions]
      assert :web in snapshot.capabilities[:tags]
      assert snapshot.profile[:age] == 3
      assert snapshot.profile[:generation] == 2
      assert snapshot.profile[:origin] == :spawned
      assert snapshot.extensions["character"] == %{persona: %{role: "Data analyst"}}
      refute Map.has_key?(snapshot.extensions, "internal")
    end

    test "snapshot returns nil when no identity" do
      agent = WebCrawlerAgent.new()
      assert IdentityAgent.snapshot(agent) == nil
    end
  end

  describe "evolution" do
    test "evolve identity with pure function" do
      identity = Identity.new(profile: %{age: 0})

      evolved = Identity.evolve(identity, years: 2)
      assert evolved.profile[:age] == 2
      assert evolved.rev == 1

      evolved = Identity.evolve(evolved, days: 730)
      assert evolved.profile[:age] == 4
      assert evolved.rev == 2
    end

    test "evolve via action" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure(profile: %{age: 0})

      {agent, []} = WebCrawlerAgent.cmd(agent, {Jido.Identity.Actions.Evolve, %{years: 3}})

      assert IdentityAgent.age(agent) == 3
    end

    test "evolution preserves capabilities and extensions" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure(profile: %{age: 0})
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_tag(:web)
        |> IdentityAgent.put_extension("character", %{level: 1})

      {agent, []} = WebCrawlerAgent.cmd(agent, {Jido.Identity.Actions.Evolve, %{years: 5}})

      assert IdentityAgent.age(agent) == 5
      assert IdentityAgent.supports_action?(agent, "FetchURL")
      assert IdentityAgent.has_tag?(agent, :web)
      assert IdentityAgent.get_extension(agent, "character").level == 1
    end
  end

  describe "orchestrator routing pattern" do
    test "filter agents by capability" do
      web_agent =
        WebCrawlerAgent.new(id: "web-1")
        |> IdentityAgent.ensure(profile: %{age: 3})
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_tag(:web)

      parser_agent =
        WebCrawlerAgent.new(id: "parser-1")
        |> IdentityAgent.ensure(profile: %{age: 1})
        |> IdentityAgent.add_action("ParseHTML")
        |> IdentityAgent.add_tag(:parsing)

      all_purpose =
        WebCrawlerAgent.new(id: "all-1")
        |> IdentityAgent.ensure(profile: %{age: 5})
        |> IdentityAgent.add_action("FetchURL")
        |> IdentityAgent.add_action("ParseHTML")
        |> IdentityAgent.add_tag(:web)
        |> IdentityAgent.add_tag(:parsing)

      agents = [web_agent, parser_agent, all_purpose]

      fetch_capable =
        agents
        |> Enum.filter(&IdentityAgent.supports_action?(&1, "FetchURL"))

      assert length(fetch_capable) == 2
      assert Enum.all?(fetch_capable, &(&1.id in ["web-1", "all-1"]))

      most_experienced =
        fetch_capable
        |> Enum.sort_by(&IdentityAgent.age/1, :desc)
        |> List.first()

      assert most_experienced.id == "all-1"
      assert IdentityAgent.age(most_experienced) == 5
    end
  end

  describe "action-based capability registration via AgentServer" do
    test "register and query capabilities through signals", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, WebCrawlerAgent, id: unique_id("crawler"))

      {:ok, _agent} =
        AgentServer.call(
          pid,
          signal("register_capabilities", %{
            actions: ["FetchURL", "ParseHTML"],
            tags: [:web, :parsing]
          })
        )

      {:ok, agent} = AgentServer.call(pid, signal("query_capabilities"))

      assert agent.state.has_identity == true
      assert agent.state.action_count == 2
      assert :web in agent.state.tags
    end

    test "evolve identity through signal", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, WebCrawlerAgent, id: unique_id("crawler"))

      {:ok, _agent} =
        AgentServer.call(
          pid,
          signal("register_capabilities", %{actions: ["FetchURL"], tags: [:web]})
        )

      {:ok, _agent} = AgentServer.call(pid, signal("evolve", %{years: 2}))
      {:ok, agent} = AgentServer.call(pid, signal("query_capabilities"))

      assert agent.state.has_identity == true
      assert agent.state.action_count == 1
    end
  end

  describe "replacing identity plugin with custom implementation" do
    test "custom plugin auto-initializes identity on agent creation" do
      agent = PreConfiguredAgent.new()

      assert IdentityAgent.has_identity?(agent)
      assert IdentityAgent.age(agent) == 5
      assert IdentityAgent.get_profile(agent, :origin) == :spawned
      assert IdentityAgent.has_tag?(agent, :web)
    end

    test "custom plugin replaces default Identity.Plugin" do
      specs = PreConfiguredAgent.plugin_specs()
      modules = Enum.map(specs, & &1.module)

      assert CustomIdentityPlugin in modules
      refute Jido.Identity.Plugin in modules
    end
  end

  describe "disabling identity plugin" do
    test "agent with __identity__ disabled has no identity capability" do
      agent = NoIdentityAgent.new()

      refute IdentityAgent.has_identity?(agent)
      refute Map.has_key?(agent.state, :__identity__)

      specs = NoIdentityAgent.plugin_specs()
      modules = Enum.map(specs, & &1.module)
      refute Jido.Identity.Plugin in modules
    end
  end
end
