defmodule JidoExampleTest.IdentityPluginTest do
  @moduledoc """
  Example test demonstrating Identity as a default plugin.

  This test shows:
  - Every agent gets `Jido.Identity.Plugin` automatically (default singleton plugin)
  - Using `Jido.Identity.Agent` and related helpers: `ensure/2`, profile management
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
  alias Jido.Identity.Profile

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
      identity = Identity.new(profile: profile)
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
      schema: []

    def signal_routes(_ctx) do
      [
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
        __identity__: {CustomIdentityPlugin, %{profile: %{age: 5, origin: :spawned}}}
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
          profile: %{age: 0, origin: :configured}
        )

      assert IdentityAgent.has_identity?(agent)
      assert Profile.age(agent) == 0
      assert Profile.get(agent, :origin) == :configured
    end
  end

  describe "snapshot for sharing identity" do
    test "snapshot includes profile data" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure(profile: %{age: 3, generation: 2, origin: :spawned})

      snapshot = IdentityAgent.snapshot(agent)

      assert snapshot.profile[:age] == 3
      assert snapshot.profile[:generation] == 2
      assert snapshot.profile[:origin] == :spawned
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

      assert Profile.age(agent) == 3
    end

    test "evolution preserves identity data" do
      agent =
        WebCrawlerAgent.new()
        |> IdentityAgent.ensure(profile: %{age: 0, origin: :test})

      {agent, []} = WebCrawlerAgent.cmd(agent, {Jido.Identity.Actions.Evolve, %{years: 5}})

      assert Profile.age(agent) == 5
      assert Profile.get(agent, :origin) == :test
    end
  end

  describe "replacing identity plugin with custom implementation" do
    test "custom plugin auto-initializes identity on agent creation" do
      agent = PreConfiguredAgent.new()

      assert IdentityAgent.has_identity?(agent)
      assert Profile.age(agent) == 5
      assert Profile.get(agent, :origin) == :spawned
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
