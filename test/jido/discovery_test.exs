defmodule Jido.DiscoveryTest do
  use ExUnit.Case, async: false

  alias Jido.Discovery

  defmodule AlphaAction do
    use Jido.Action,
      name: "alpha_action",
      description: "Alpha catalog fixture"

    @impl true
    def run(params, _context), do: {:ok, params}
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
    @doc false
    def __jido_executable__, do: Jido.Executable.flow(__MODULE__)
  end

  defmodule InvalidAction do
    @doc false
    def __jido_executable__, do: Jido.Executable.action(__MODULE__)
  end

  defmodule InvalidMetadataAction do
    @doc false
    def __jido_executable__, do: Jido.Executable.action(__MODULE__)

    @doc false
    def validate_params(params), do: {:ok, params}

    @doc false
    def validate_output(output), do: {:ok, output}

    @doc false
    def run(params, _context), do: {:ok, params}

    @doc false
    def name, do: :not_a_string

    @doc false
    def description, do: nil
  end

  setup_all do
    on_exit(fn -> Discovery.refresh() end)
    :ok
  end

  test "builds one deterministic Action catalog from explicit modules" do
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
                 Jido.DiscoveryTest.MissingAction
               ]
             )

    assert Discovery.ready?()

    assert {:ok,
            %{
              version: 1,
              built_at: %DateTime{},
              actions: [alpha, beta],
              diagnostics: [
                %{module: InvalidAction, error: _invalid_error},
                %{
                  module: InvalidMetadataAction,
                  error: {:invalid_action_metadata, %{name: :not_a_string, description: nil}}
                },
                %{
                  module: Jido.DiscoveryTest.MissingAction,
                  error: {:module_not_loaded, :nofile}
                }
              ]
            }} = Discovery.catalog()

    assert alpha.module == AlphaAction
    assert alpha.name == "alpha_action"
    assert alpha.description == "Alpha catalog fixture"
    assert byte_size(alpha.slug) == 16

    assert beta.module == BetaAction
    assert Discovery.get_action(AlphaAction) == alpha
    assert Discovery.get_action_by_slug(beta.slug) == beta
    assert Discovery.get_action(InlineAction) == nil
    assert Discovery.get_action(FlowDescriptor) == nil
    assert Discovery.get_action_by_slug("missing") == nil
    assert {:ok, %DateTime{}} = Discovery.last_updated()
  end

  test "filters and pages Action metadata" do
    assert :ok =
             Discovery.refresh(
               applications: [],
               modules: [BetaAction, AlphaAction, NoDescriptionAction]
             )

    assert [%{module: AlphaAction}] = Discovery.list_actions(name: "alpha")
    assert [%{module: BetaAction}] = Discovery.list_actions(description: "Beta")
    assert [] = Discovery.list_actions(name: :alpha)
    assert [] = Discovery.list_actions(description: "missing")
    assert [] = Discovery.list_actions(application: :missing)

    assert [%{application: application} | _] = Discovery.list_actions()
    assert length(Discovery.list_actions(application: application)) == 3
    assert [%{module: AlphaAction}] = Discovery.list_actions(offset: -1, limit: 1)
    assert [%{module: BetaAction}] = Discovery.list_actions(offset: 1, limit: 1)
    assert [] = Discovery.list_actions(limit: 0)
  end

  test "reports that the catalog is not ready before its first build" do
    :persistent_term.erase({Jido.Discovery, :catalog})

    refute Discovery.ready?()
    assert Discovery.catalog() == {:error, :not_initialized}
    assert Discovery.last_updated() == {:error, :not_initialized}
    assert Discovery.list_actions() == []
    assert Discovery.get_action(AlphaAction) == nil
    assert Discovery.get_action_by_slug("missing") == nil

    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
  end

  test "keeps the current catalog when refresh options are invalid" do
    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
    assert {:ok, catalog} = Discovery.catalog()

    assert {:error, {:invalid_modules, ["not-a-module"]}} =
             Discovery.refresh(applications: [], modules: ["not-a-module"])

    assert {:error, {:invalid_applications, ["not-an-application"]}} =
             Discovery.refresh(applications: ["not-an-application"])

    assert {:error, {:invalid_applications, :started}} =
             Discovery.refresh(applications: :started)

    assert {:error, {:invalid_modules, :all}} =
             Discovery.refresh(applications: [], modules: :all)

    assert {:error, {:application_not_loaded, :not_an_application}} =
             Discovery.refresh(applications: [:not_an_application])

    assert Discovery.catalog() == {:ok, catalog}
  end

  test "defines a temporary startup Task" do
    assert %{
             id: Jido.Discovery,
             restart: :temporary,
             type: :worker,
             start: {Task, :start_link, [loader]}
           } = Discovery.child_spec(applications: [], modules: [AlphaAction])

    assert is_function(loader, 0)
  end
end
