defmodule Jido.Authoring.DiscoveryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Authoring.{Manifest, Registry}
  alias Jido.Discovery

  defmodule AlphaAction do
    use Jido.Action,
      id: "tests/actions/alpha",
      vsn: 2,
      name: "alpha_action",
      description: "Alpha catalog fixture"

    @impl true
    def run(_params, _context), do: raise("discovery must not run Actions")
  end

  defmodule BetaAction do
    use Jido.Action,
      id: "tests/actions/beta",
      name: "beta_action",
      description: "Beta catalog fixture"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule AlphaActionV1 do
    use Jido.Action,
      id: "tests/actions/alpha",
      vsn: 1,
      name: "alpha_action_v1"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule AlphaFlow do
    use Jido.Flow,
      id: "tests/flows/alpha",
      vsn: 3,
      name: "alpha_flow"

    flow do
      step "beta", action: Jido.Authoring.DiscoveryTest.BetaAction, params: %{}
      output(result("beta"))
    end
  end

  defmodule DuplicateAction do
    use Jido.Action,
      id: "tests/actions/alpha",
      vsn: 2,
      name: "duplicate_action"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Vocabulary do
    def __jido_authoring__ do
      [
        %{
          id: "tests/atoms/name",
          kind: :atom,
          vsn: 1,
          target: :name,
          name: "name"
        },
        %{
          id: "tests/schemas/name",
          kind: :schema,
          vsn: 1,
          target: Jido.Joi.object(%{name: Jido.Joi.string()}),
          name: "name input"
        }
      ]
    end
  end

  defmodule BareVocabulary do
    def __jido_authoring__ do
      %{
        id: "tests/atoms/bare",
        kind: :atom,
        vsn: 1,
        target: :bare
      }
    end
  end

  defmodule InvalidManifest do
    def __jido_authoring__, do: %{kind: :atom}
  end

  setup do
    catalog = :persistent_term.get({Jido.Discovery, :registry}, :not_initialized)
    config = Application.get_env(:jido, Jido.Discovery)

    on_exit(fn ->
      if catalog == :not_initialized,
        do: :persistent_term.erase({Jido.Discovery, :registry}),
        else: :persistent_term.put({Jido.Discovery, :registry}, catalog)

      if config == nil,
        do: Application.delete_env(:jido, Jido.Discovery),
        else: Application.put_env(:jido, Jido.Discovery, config)
    end)

    :ok
  end

  test "Action and Flow modules expose static authoring manifests" do
    assert AlphaAction.__jido_authoring__() == %{
             id: "tests/actions/alpha",
             kind: :action,
             vsn: 2,
             target: AlphaAction,
             name: "alpha_action",
             description: "Alpha catalog fixture"
           }

    assert AlphaFlow.__jido_authoring__() == %{
             id: "tests/flows/alpha",
             kind: :flow,
             vsn: 3,
             target: AlphaFlow,
             name: "alpha_flow",
             description: nil
           }
  end

  test "builds one immutable catalog and Registry without running discovered work" do
    assert :ok =
             Discovery.refresh(
               applications: [],
               modules: [AlphaFlow, Jido.Flow.Codec, BetaAction, AlphaAction, AlphaActionV1]
             )

    assert %Registry{} = catalog = Discovery.registry()
    assert Discovery.ready?()
    assert catalog.revision =~ ~r/^[A-Za-z0-9_-]{43}$/

    assert %{target: AlphaAction, vsn: 2} =
             Registry.get(catalog, :action, "tests/actions/alpha", 2)

    assert %{target: AlphaActionV1, vsn: 1} =
             Registry.get(catalog, :action, "tests/actions/alpha", 1)

    assert %{target: AlphaFlow, vsn: 3} =
             Registry.get(catalog, :flow, "tests/flows/alpha", 3)

    assert Registry.codec(catalog, "jido.flow", 2) == {:ok, Jido.Flow.Codec}
    assert %Registry{} = registry = Discovery.registry()

    assert Registry.resolve(registry, {"tests/actions/alpha", 2}, :action) ==
             {:ok, AlphaAction}

    assert Registry.resolve(registry, {"tests/actions/alpha", 1}, :action) ==
             {:ok, AlphaActionV1}

    assert Registry.resolve(registry, {"tests/flows/alpha", 3}, :flow) ==
             {:ok, AlphaFlow}

    assert Registry.resolve(registry, {"jido/schemas/map", 1}, :schema) ==
             {:ok, Jido.Joi.map()}

    assert [%{target: AlphaActionV1}, %{target: AlphaAction}, %{target: BetaAction}] =
             Discovery.list(:action)

    assert [%{target: AlphaFlow}] = Discovery.list(:flow)
    assert %{target: AlphaAction} = Discovery.get("tests/actions/alpha", 2)
    assert %{target: AlphaActionV1} = Discovery.get("tests/actions/alpha", 1)
    assert %{target: AlphaAction} = Discovery.get_by_target(:action, AlphaAction)
  end

  test "accepts static vocabulary entries from an application module" do
    assert :ok = Discovery.refresh(applications: [], modules: [Vocabulary])
    catalog = Discovery.registry()

    assert %{target: :name, provider: Vocabulary} =
             Registry.get(catalog, :atom, "tests/atoms/name", 1)

    assert %{provider: Vocabulary} = Registry.get(catalog, :schema, "tests/schemas/name", 1)

    assert Registry.resolve(
             catalog,
             {"tests/atoms/name", 1},
             :atom
           ) == {:ok, :name}
  end

  test "lists manifests without display text" do
    assert :ok = Discovery.refresh(applications: [], modules: [BareVocabulary])

    assert [entry] = Discovery.list(:atom)
    assert entry.id == "tests/atoms/bare"
    refute Map.has_key?(entry, :name)
    refute Map.has_key?(entry, :description)
  end

  test "catalog revision changes when a registered target changes" do
    assert {:ok, first} =
             Registry.new_discovered(
               [manifest("tests/schemas/revision", :schema, Jido.Joi.object(%{a: Jido.Joi.string()}))],
               []
             )

    assert {:ok, second} =
             Registry.new_discovered(
               [manifest("tests/schemas/revision", :schema, Jido.Joi.object(%{b: Jido.Joi.integer()}))],
               []
             )

    refute first.revision == second.revision
  end

  test "catalog revision includes public display metadata" do
    first = manifest("tests/schemas/revision", :schema, Jido.Joi.object(%{value: Jido.Joi.string()}))
    second = %{first | name: "Changed name"}

    assert {:ok, first_catalog} = Registry.new_discovered([first], [])
    assert {:ok, second_catalog} = Registry.new_discovered([second], [])
    refute first_catalog.revision == second_catalog.revision
  end

  test "rejects invalid core manifest targets" do
    assert {:error, {:invalid_authoring_manifest, __MODULE__, :kind}} =
             Manifest.validate(
               __MODULE__,
               %{id: "tests/invalid-kind", kind: true, vsn: 1, target: :name}
             )

    assert {:error, {:invalid_authoring_manifest, __MODULE__, {:target, _}}} =
             Manifest.validate(
               __MODULE__,
               %{id: "tests/atoms/invalid", kind: :atom, vsn: 1, target: "name"}
             )

    assert {:error, {:invalid_authoring_manifest, __MODULE__, {:target, _}}} =
             Manifest.validate(
               __MODULE__,
               %{id: "tests/schemas/invalid", kind: :schema, vsn: 1, target: self()}
             )
  end

  test "rejects duplicate stable IDs without replacing the current catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
    catalog = Discovery.registry()

    assert {:error, {:duplicate_authoring_reference, {"tests/actions/alpha", 2}}} =
             Discovery.refresh(
               applications: [],
               modules: [AlphaAction, DuplicateAction]
             )

    assert Discovery.registry() == catalog
  end

  test "rejects a failed module scan without replacing the current catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
    catalog = Discovery.registry()

    assert {:error, {:invalid_authoring_manifest, InvalidManifest, _reason}} =
             Discovery.refresh(applications: [], modules: [BetaAction, InvalidManifest])

    assert Discovery.registry() == catalog
  end

  test "uses jido_action configuration and initializes synchronously" do
    Application.put_env(:jido, Jido.Discovery,
      applications: [],
      modules: [BetaAction, AlphaFlow]
    )

    assert :ok = Discovery.initialize(modules: [AlphaAction])
    assert Enum.map(Discovery.list(:action), & &1.target) == [AlphaAction, BetaAction]
    assert Enum.map(Discovery.list(:flow), & &1.target) == [AlphaFlow]
  end

  test "provides a temporary Task child specification" do
    opts = [applications: [], modules: [AlphaAction]]

    assert %{
             id: Jido.Discovery,
             start: {Task, :start_link, [initializer]},
             restart: :temporary,
             type: :worker
           } = Discovery.child_spec(opts)

    assert is_function(initializer, 0)
  end

  test "retains the latest asynchronous scan failure" do
    :persistent_term.erase({Jido.Discovery, :registry})

    assert %{
             start: {Task, :start_link, [initializer]}
           } = Discovery.child_spec(applications: :bad)

    assert capture_log(initializer) =~ "Jido Discovery did not refresh"
    refute Discovery.ready?()

    error = assert_raise Jido.Authoring.Error.InternalError, &Discovery.registry/0
    assert error.code == :registry_initialization_failed
    assert error.details == %{reason: {:invalid_applications, :bad}}

    assert %{start: {Task, :start_link, [retry]}} =
             Discovery.child_spec(applications: [], modules: :bad)

    assert capture_log(retry) =~ "Jido Discovery did not refresh"

    error = assert_raise Jido.Authoring.Error.InternalError, &Discovery.registry/0
    assert error.details == %{reason: {:invalid_modules, :bad}}
  end

  test "an asynchronous scan failure does not replace a valid Registry" do
    assert :ok = Discovery.refresh(applications: [], modules: [AlphaAction])
    registry = Discovery.registry()

    assert %{start: {Task, :start_link, [initializer]}} =
             Discovery.child_spec(applications: :bad)

    assert capture_log(initializer) =~ "Jido Discovery did not refresh"
    assert Discovery.registry() == registry
  end

  test "fails before initialization and rejects invalid scan options" do
    :persistent_term.erase({Jido.Discovery, :registry})
    refute Discovery.ready?()

    for operation <- [
          &Discovery.registry/0,
          &Discovery.list/0,
          fn -> Discovery.get("missing", 1) end,
          fn -> Discovery.get_by_target(:atom, :missing) end
        ] do
      assert_raise Jido.Authoring.Error.InternalError,
                   "authoring Registry is not initialized",
                   operation
    end

    assert {:error, {:invalid_applications, :bad}} = Discovery.refresh(applications: :bad)
    assert {:error, {:invalid_modules, :bad}} = Discovery.refresh(applications: [], modules: :bad)

    missing = Module.concat(__MODULE__, "Missing")

    assert {:error, {:module_not_loaded, :nofile}} =
             Discovery.refresh(applications: [], modules: [missing])

    assert {:error, {:invalid_discovery_options, [:unknown]}} =
             Discovery.refresh(applications: [], unknown: true)

    Application.put_env(:jido, Jido.Discovery, :bad)
    assert {:error, {:invalid_discovery_config, :bad}} = Discovery.refresh()

    Application.put_env(:jido, Jido.Discovery, unknown: true)

    assert {:error, {:invalid_discovery_config, {:unknown_options, [:unknown]}}} =
             Discovery.refresh()
  end

  test "the default startup scan includes all loaded applications" do
    Application.delete_env(:jido, Jido.Discovery)

    assert :ok = Discovery.initialize()
    catalog = Discovery.registry()
    assert Registry.codec(catalog, "jido.flow", 2) == {:ok, Jido.Flow.Codec}
  end

  defp manifest(id, kind, target) do
    %{
      id: id,
      kind: kind,
      vsn: 1,
      target: target,
      provider: Vocabulary,
      name: nil,
      description: nil,
      application: nil
    }
  end
end
