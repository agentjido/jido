defmodule Jido.Plugin.AfterCommitTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.Plugin, as: ServerPlugin
  alias Jido.Plugin
  alias JidoTest.CommitProjection.{AgentFacet, NotificationFacet, Stateless}

  defmodule Mapped do
    @moduledoc false
    use Jido.Plugin,
      agent: AgentFacet,
      agent_server: NotificationFacet,
      option_keys: [agent: [:key], agent_server: [:sink]]
  end

  defmodule Legacy do
    @moduledoc false
    use Jido.Plugin
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule Manifest do
    @moduledoc false
    use Jido.Plugin, agent_server: NotificationFacet
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule WrongAgent do
    @moduledoc false
    use Jido.Agent.Plugin
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule WrongPersistence do
    @moduledoc false
    use Jido.Persistence.Plugin
    def dump(value, _context, _opts), do: {:ok, value}
    def load(value, _context, _opts), do: {:ok, value}
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule WrongTopology do
    @moduledoc false
    use Jido.Topology.Plugin
    def contribute(_context, _opts), do: {:error, :unused}
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule AgentPackage do
    @moduledoc false
    use Jido.Plugin, agent: WrongAgent
  end

  defmodule PersistencePackage do
    @moduledoc false
    use Jido.Plugin, agent: AgentFacet, persistence: WrongPersistence
  end

  defmodule TopologyPackage do
    @moduledoc false
    use Jido.Plugin, topology: WrongTopology
  end

  test "a commit-only Server facet needs no runtime or Agent facet" do
    assert {:ok, [spec]} = Plugin.normalize_all([{Stateless, sink: :sink}])
    refute spec.runtime?
    assert spec.agent_server.module == NotificationFacet
    assert ServerPlugin.commit_modules([spec]) == [Stateless]
  end

  test "commit options stay within the selected owner facet" do
    assert {:ok, [spec]} = Plugin.normalize_all([{Mapped, key: :projection, sink: :sink}])
    assert spec.agent.options == [key: :projection]
    assert spec.agent_server.options == [sink: :sink]
  end

  for package <- [Legacy, Manifest, AgentPackage, PersistencePackage, TopologyPackage] do
    @package package
    test "#{inspect(package)} cannot take Server commit authority" do
      assert {:error, %Jido.Error.ValidationError{details: %{callback: {:after_commit, 3}}}} =
               Plugin.normalize_all([{@package, key: :owned}])
    end
  end
end
