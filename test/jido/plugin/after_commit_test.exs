defmodule Jido.Plugin.AfterCommitTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.Plugin.Callbacks
  alias JidoTest.CommitProjection.Stateless

  defmodule Mapped do
    @moduledoc false
    use Jido.Plugin, option_keys: [agent: [:key], agent_server: [:sink]]

    @impl true
    defdelegate state_spec(opts), to: JidoTest.CommitProjection.AgentFacet

    @impl true
    defdelegate directives(opts), to: JidoTest.CommitProjection.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: JidoTest.CommitProjection.AgentFacet

    @impl true
    defdelegate after_commit(runtime, commit, opts),
      to: JidoTest.CommitProjection.NotificationFacet
  end

  defmodule Legacy do
    @moduledoc false
    def __jido_plugin__, do: :agent
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule Manifest do
    @moduledoc false
    use Jido.Plugin
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule WrongAgent do
    @moduledoc false
    @behaviour Jido.Plugin
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule WrongPersistence do
    @moduledoc false
    @behaviour Jido.Plugin
    def dump(value, _context, _opts), do: {:ok, value}
    def load(value, _context, _opts), do: {:ok, value}
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule WrongTopology do
    @moduledoc false
    @behaviour Jido.Plugin
    def contribute(_context, _opts), do: {:error, :unused}
    def after_commit(_runtime, _commit, _opts), do: :ok
  end

  defmodule AgentPackage do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate after_commit(runtime, commit, opts), to: Jido.Plugin.AfterCommitTest.WrongAgent
  end

  defmodule PersistencePackage do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: JidoTest.CommitProjection.AgentFacet

    @impl true
    defdelegate directives(opts), to: JidoTest.CommitProjection.AgentFacet

    @impl true
    defdelegate reduce(reduction, opts), to: JidoTest.CommitProjection.AgentFacet

    @impl true
    defdelegate dump(value, context, opts), to: Jido.Plugin.AfterCommitTest.WrongPersistence

    @impl true
    defdelegate load(value, context, opts), to: Jido.Plugin.AfterCommitTest.WrongPersistence

    @impl true
    defdelegate after_commit(runtime, commit, opts),
      to: Jido.Plugin.AfterCommitTest.WrongPersistence
  end

  defmodule TopologyPackage do
    @moduledoc false
    use Jido.Plugin

    @impl true
    defdelegate contribute(context, opts), to: Jido.Plugin.AfterCommitTest.WrongTopology

    @impl true
    defdelegate after_commit(runtime, commit, opts), to: Jido.Plugin.AfterCommitTest.WrongTopology
  end

  test "a commit-only Server facet needs no runtime or Agent facet" do
    assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{Stateless, sink: :sink}])
    refute spec.agent_server.runtime?
    assert spec.agent_server.module == Stateless
    assert Callbacks.commit_specs([spec]) == [spec]
  end

  test "commit options stay within the selected owner facet" do
    assert {:ok, [spec]} =
             Jido.Plugin.Normalizer.normalize_all([{Mapped, key: :projection, sink: :sink}])

    assert spec.agent.options == [key: :projection]
    assert spec.agent_server.options == [sink: :sink]
  end

  for package <- [Manifest, AgentPackage, PersistencePackage, TopologyPackage] do
    @package package
    test "#{inspect(package)} can combine a commit hook with other callbacks" do
      assert {:ok, [spec]} = Jido.Plugin.Normalizer.normalize_all([{@package, key: :owned}])
      assert spec.agent_server.module == @package
      refute spec.agent_server.runtime?
      assert Callbacks.commit_specs([spec]) == [spec]
    end
  end

  test "bare Plugin markers cannot take Server commit authority" do
    assert {:error, %{message: "Plugin must use Jido.Plugin"}} =
             Jido.Plugin.Normalizer.normalize_all([Legacy])
  end
end
