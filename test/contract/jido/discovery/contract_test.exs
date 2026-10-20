defmodule JidoTest.Discovery.ContractTest do
  use Covenant.Case, component: "jido.discovery", async: false

  alias Jido.Discovery

  defmodule AlphaAction do
    use Jido.Action,
      name: "alpha_action",
      description: "Alpha catalog fixture"

    @impl true
    def run(_params, _context), do: raise("discovery must not run Actions")
  end

  defmodule BetaAction do
    use Jido.Action,
      name: "beta_action",
      description: "Beta catalog fixture"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule NoDescriptionAction do
    use Jido.Action, name: "no_description_action"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule InlineAction do
    use Jido.Action, name: "private_inline_action"

    @impl true
    def run(params, _context), do: {:ok, params}

    @doc false
    def __jido_inline_action__, do: {__MODULE__, [role: :action]}
  end

  defmodule FlowDescriptor do
    @behaviour Jido.Flow

    @impl true
    def flow, do: raise("discovery must not build Flows")
    @impl true
    def validate_params(params), do: {:ok, params}
    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule InvalidAction do
    @behaviour Jido.Action
    @impl true
    def run(params, _context), do: {:ok, params}
    @impl true
    def validate_params(params), do: {:ok, params}
    @impl true
    def validate_output(output), do: {:ok, output}
  end

  defmodule InvalidMetadataAction do
    @behaviour Jido.Action

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}

    @impl true
    def run(params, _context), do: {:ok, params}

    @doc false
    def name, do: :not_a_string

    @doc false
    def description, do: nil
  end

  defmodule RaisedMetadataAction do
    @behaviour Jido.Action

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}

    @impl true
    def run(params, _context), do: {:ok, params}

    def name, do: raise("metadata failed")

    def description, do: nil
  end

  defmodule ThrownMetadataAction do
    @behaviour Jido.Action

    @impl true
    def validate_params(params), do: {:ok, params}

    @impl true
    def validate_output(output), do: {:ok, output}

    @impl true
    def run(params, _context), do: {:ok, params}

    def name, do: throw(:metadata_failed)

    def description, do: nil
  end

  setup_all do
    catalog = :persistent_term.get({Jido.Discovery, :catalog}, :not_initialized)

    on_exit(fn ->
      if catalog == :not_initialized,
        do: :persistent_term.erase({Jido.Discovery, :catalog}),
        else: :persistent_term.put({Jido.Discovery, :catalog}, catalog)
    end)

    :ok
  end

  @tag obligation: ["jido.discovery.I3", "jido.discovery.I4"]
  test "builds one deterministic Action catalog without executing discovered work" do
    missing = Module.concat(__MODULE__, MissingAction)

    assert :ok =
             Discovery.refresh(
               applications: [],
               modules: [
                 BetaAction,
                 InlineAction,
                 AlphaAction,
                 FlowDescriptor,
                 InvalidAction,
                 InvalidMetadataAction,
                 RaisedMetadataAction,
                 ThrownMetadataAction,
                 String,
                 missing
               ]
             )

    assert Discovery.ready?()

    assert {:ok,
            %{
              version: 1,
              built_at: %DateTime{},
              actions: [alpha, beta],
              diagnostics: diagnostics
            }} = Discovery.catalog()

    assert alpha.module == AlphaAction
    assert alpha.name == "alpha_action"
    assert alpha.description == "Alpha catalog fixture"
    assert alpha.slug == "-1IYA0rkxHYIULgB"
    assert Base.url_decode64(alpha.slug, padding: false) |> elem(0) == :ok

    assert beta.module == BetaAction
    assert Discovery.get_action(AlphaAction) == alpha
    assert Discovery.get_action_by_slug(beta.slug) == beta
    assert Discovery.get_action(InlineAction) == nil
    assert Discovery.get_action(FlowDescriptor) == nil
    assert Discovery.get_action_by_slug("missing") == nil
    assert {:ok, %DateTime{}} = Discovery.last_updated()

    assert Enum.map(diagnostics, & &1.module) ==
             diagnostics |> Enum.map(& &1.module) |> Enum.sort()

    by_module = Map.new(diagnostics, &{&1.module, &1.error})
    assert Map.has_key?(by_module, InvalidAction)
    refute Map.has_key?(by_module, String)

    assert by_module[InvalidMetadataAction] ==
             {:invalid_action_metadata, %{name: :not_a_string, description: nil}}

    assert {:action_metadata_failed, %RuntimeError{message: "metadata failed"}} =
             by_module[RaisedMetadataAction]

    assert by_module[ThrownMetadataAction] ==
             {:action_metadata_failed, {:throw, :metadata_failed}}

    assert by_module[missing] == {:module_not_loaded, :nofile}

    slug = alpha.slug
    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
    assert %{slug: ^slug} = Discovery.get_action(AlphaAction)
  end

  @tag obligation: "jido.discovery.I5"
  test "filters and pages Action metadata" do
    assert :ok =
             Discovery.refresh(
               applications: [],
               modules: [BetaAction, AlphaAction, NoDescriptionAction]
             )

    assert [%{module: AlphaAction}] = Discovery.list_actions(name: "alpha")
    assert [] = Discovery.list_actions(name: "Alpha")
    assert [%{module: BetaAction}] = Discovery.list_actions(description: "Beta")
    assert [] = Discovery.list_actions(name: :alpha)
    assert [] = Discovery.list_actions(description: "missing")
    assert [] = Discovery.list_actions(application: :missing)

    assert [%{application: application} | _] = Discovery.list_actions()
    assert length(Discovery.list_actions(application: application)) == 3
    assert [%{module: AlphaAction}] = Discovery.list_actions(offset: -1, limit: 1)
    assert [%{module: AlphaAction}] = Discovery.list_actions(offset: :invalid, limit: 1)
    assert [%{module: BetaAction}] = Discovery.list_actions(offset: 1, limit: 1)
    assert length(Discovery.list_actions(offset: -1)) == 3
    assert length(Discovery.list_actions(offset: :invalid)) == 3
    assert length(Discovery.list_actions(limit: :all)) == 3
    assert length(Discovery.list_actions(limit: -1)) == 3
    assert [] = Discovery.list_actions(limit: 0)
  end

  @tag obligation: "jido.discovery.I1"
  test "reports explicit empty reads before its first successful build" do
    :persistent_term.erase({Jido.Discovery, :catalog})

    assert Discovery.ready?() == false
    assert Discovery.catalog() == {:error, :not_initialized}
    assert Discovery.last_updated() == {:error, :not_initialized}
    assert Discovery.list_actions() == []
    assert Discovery.get_action(AlphaAction) == nil
    assert Discovery.get_action_by_slug("missing") == nil

    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
  end

  @tag obligation: "jido.discovery.I2"
  test "rejects invalid scan sources without replacing the current catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
    assert {:ok, catalog} = Discovery.catalog()

    for {opts, error} <- [
          {[applications: [], modules: ["not-a-module"]], {:invalid_modules, ["not-a-module"]}},
          {[applications: ["not-an-application"]],
           {:invalid_applications, ["not-an-application"]}},
          {[applications: :started], {:invalid_applications, :started}},
          {[applications: [], modules: :all], {:invalid_modules, :all}},
          {[applications: [:not_an_application]], {:application_not_loaded, :not_an_application}}
        ] do
      assert Discovery.refresh(opts) == {:error, error}
      assert Discovery.catalog() == {:ok, catalog}
    end
  end

  @tag obligation: "jido.discovery.I2"
  test "combines configured and explicit modules and replaces stale entries" do
    restore_config_after_test()

    Application.put_env(:jido, Jido.Discovery, applications: [], modules: [BetaAction])

    assert :ok = Discovery.refresh(modules: [AlphaAction, AlphaAction])
    assert Enum.map(Discovery.list_actions(), & &1.module) == [AlphaAction, BetaAction]

    Application.put_env(:jido, Jido.Discovery, applications: [], modules: [])
    assert :ok = Discovery.refresh(modules: [NoDescriptionAction])
    assert [%{module: NoDescriptionAction}] = Discovery.list_actions()
    assert Discovery.get_action(AlphaAction) == nil

    Application.put_env(:jido, Jido.Discovery, %{modules: []})
    assert {:error, {:invalid_discovery_config, %{modules: []}}} = Discovery.refresh()
    assert [%{module: NoDescriptionAction}] = Discovery.list_actions()
  end

  @tag obligation: "jido.discovery.I2"
  test "uses loaded applications by default and supports one application" do
    restore_config_after_test()
    Application.delete_env(:jido, Jido.Discovery)

    assert :ok = Discovery.refresh()

    assert %{module: Jido.Agent.Turn.SignalHandler, application: :jido} =
             Discovery.get_action(Jido.Agent.Turn.SignalHandler)

    assert :ok = Discovery.refresh(applications: [:jido], modules: [])

    assert %{module: Jido.Agent.Turn.SignalHandler} =
             Discovery.get_action(Jido.Agent.Turn.SignalHandler)

    assert [%{module: Jido.Agent.Turn.SignalHandler}] =
             Discovery.list_actions(application: :jido, name: "signal_handler")

    assert Discovery.list_actions(application: :other, name: "signal_handler") == []
  end

  @tag obligation: "jido.discovery.I1"
  test "defines a temporary startup Task and contains build failure" do
    assert %{start: {Task, :start_link, [valid_loader]}} =
             Discovery.child_spec(applications: [], modules: [AlphaAction])

    assert valid_loader.() == :ok
    assert %{module: AlphaAction} = Discovery.get_action(AlphaAction)

    assert %{
             id: Jido.Discovery,
             restart: :temporary,
             type: :worker,
             start: {Task, :start_link, [loader]}
           } = Discovery.child_spec(applications: :invalid)

    assert is_function(loader, 0)
    assert loader.() == :ok
  end

  defp restore_config_after_test do
    previous = Application.get_env(:jido, Jido.Discovery)

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:jido, Jido.Discovery),
        else: Application.put_env(:jido, Jido.Discovery, previous)
    end)
  end
end
