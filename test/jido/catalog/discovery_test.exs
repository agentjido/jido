defmodule Jido.Catalog.DiscoveryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Catalog
  alias Jido.Catalog.{Discovery, Entry, Manifest}
  alias Jido.Codec.Index

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
      step "beta", action: Jido.Catalog.DiscoveryTest.BetaAction, params: %{}
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

  defmodule PackageAction do
    use Jido.Action,
      id: "tests/actions/package",
      name: "package_action"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Vocabulary do
    def __jido_catalog_manifest__ do
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
    def __jido_catalog_manifest__ do
      %{
        id: "tests/atoms/bare",
        kind: :atom,
        vsn: 1,
        target: :bare
      }
    end
  end

  defmodule BlockingManifest do
    def __jido_catalog_manifest__ do
      send(Jido.Catalog.DiscoveryTest, {:scan_started, self()})

      receive do
        :continue -> [%{id: "discovery_test/scanned", kind: :atom, vsn: 1, target: :scanned}]
      end
    end
  end

  defmodule InvalidManifest do
    def __jido_catalog_manifest__, do: %{kind: :atom}
  end

  setup do
    catalog = :persistent_term.get({:jido, :catalog_snapshot}, :not_initialized)
    config = Application.get_env(:jido, Jido.Catalog.Discovery)

    on_exit(fn ->
      if catalog == :not_initialized,
        do: :persistent_term.erase({:jido, :catalog_snapshot}),
        else: :persistent_term.put({:jido, :catalog_snapshot}, catalog)

      if config == nil,
        do: Application.delete_env(:jido, Jido.Catalog.Discovery),
        else: Application.put_env(:jido, Jido.Catalog.Discovery, config)
    end)

    :ok
  end

  test "Action and Flow modules expose static authoring manifests" do
    assert AlphaAction.__jido_catalog_manifest__() == %{
             id: "tests/actions/alpha",
             kind: :action,
             vsn: 2,
             target: AlphaAction,
             name: "alpha_action",
             description: "Alpha catalog fixture"
           }

    assert AlphaFlow.__jido_catalog_manifest__() == %{
             id: "tests/flows/alpha",
             kind: :flow,
             vsn: 3,
             target: AlphaFlow,
             name: "alpha_flow",
             description: nil
           }
  end

  test "builds one immutable Catalog and Codec Index without running discovered work" do
    assert :ok =
             Discovery.refresh(
               applications: [],
               modules: [
                 {AlphaFlow, :jido},
                 {Jido.Flow.Codec, :jido},
                 {BetaAction, :jido},
                 {AlphaAction, :jido},
                 {AlphaActionV1, :jido}
               ]
             )

    assert %Catalog{} = catalog = Discovery.catalog()
    assert %Index{} = codecs = Discovery.codec_index()
    assert Discovery.ready?()
    assert Catalog.revision(catalog) =~ ~r/^[A-Za-z0-9_-]{43}$/

    assert %Entry{target: AlphaAction, vsn: 2} =
             Catalog.get(catalog, :action, "tests/actions/alpha", 2)

    assert %Entry{target: AlphaActionV1, vsn: 1} =
             Catalog.get(catalog, :action, "tests/actions/alpha", 1)

    assert %Entry{target: AlphaFlow, vsn: 3} =
             Catalog.get(catalog, :flow, "tests/flows/alpha", 3)

    assert Index.codec(codecs, "jido.flow", 2) == {:ok, Jido.Flow.Codec}

    assert Catalog.resolve(catalog, {"tests/actions/alpha", 2}, :action) ==
             {:ok, AlphaAction}

    assert Catalog.resolve(catalog, {"tests/actions/alpha", 1}, :action) ==
             {:ok, AlphaActionV1}

    assert Catalog.resolve(catalog, {"tests/flows/alpha", 3}, :flow) ==
             {:ok, AlphaFlow}

    assert Catalog.resolve(catalog, {"jido/schemas/map", 1}, :schema) ==
             {:ok, Jido.Joi.map()}

    assert [%Entry{target: AlphaActionV1}, %Entry{target: AlphaAction}, %Entry{target: BetaAction}] =
             Discovery.list(:action)

    assert [%Entry{target: AlphaFlow}] = Discovery.list(:flow)
    assert %Entry{target: AlphaAction} = Discovery.get("tests/actions/alpha", 2)
    assert %Entry{target: AlphaActionV1} = Discovery.get("tests/actions/alpha", 1)
    assert %Entry{target: AlphaAction} = Discovery.get_by_target(:action, AlphaAction)
  end

  test "accepts static vocabulary entries from an application module" do
    assert :ok = Discovery.refresh(applications: [], modules: [{Vocabulary, :jido}])
    catalog = Discovery.catalog()

    assert %Entry{target: :name, provider: Vocabulary} =
             Catalog.get(catalog, :atom, "tests/atoms/name", 1)

    assert %Entry{provider: Vocabulary} = Catalog.get(catalog, :schema, "tests/schemas/name", 1)

    assert Catalog.resolve(
             catalog,
             {"tests/atoms/name", 1},
             :atom
           ) == {:ok, :name}
  end

  test "discovers a deterministic contribution from an extension OTP application" do
    application = :jido_catalog_fixture

    assert :ok =
             :application.load(
               {:application, application,
                [
                  description: ~c"Jido Catalog fixture",
                  vsn: ~c"1",
                  modules: [PackageAction],
                  registered: [],
                  applications: [:kernel, :stdlib]
                ]}
             )

    on_exit(fn -> :application.unload(application) end)

    assert :ok = Discovery.refresh(applications: [application])
    first = Discovery.catalog()

    assert %Entry{
             target: PackageAction,
             provider: PackageAction,
             application: ^application
           } = Catalog.get(first, :action, "tests/actions/package", 1)

    assert :ok = Discovery.refresh(applications: [application])
    assert Catalog.revision(Discovery.catalog()) == Catalog.revision(first)
  end

  test "publishes the exact included Plugin list through the Catalog" do
    assert Discovery.included_plugins() == [
             Jido.AI.Agent.Plugin,
             Jido.Plugin.Scheduler,
             Jido.Plugin.SensorManager,
             Jido.Plugin.Bus.Manager,
             Jido.Plugin.Bus.Client,
             Jido.Plugin.Heartbeat,
             Jido.Plugin.Audit
           ]

    assert :ok = Discovery.refresh(applications: [:jido])

    assert Enum.all?(Discovery.included_plugins(), fn plugin ->
             match?(%Entry{target: ^plugin}, Discovery.get_by_target(:plugin, plugin))
           end)
  end

  test "lists manifests without display text" do
    assert :ok = Discovery.refresh(applications: [], modules: [{BareVocabulary, :jido}])

    assert [entry] = Discovery.list(:atom)
    assert entry.id == "tests/atoms/bare"
    assert entry.name == nil
    assert entry.description == nil
  end

  test "catalog revision changes when a registered target changes" do
    assert {:ok, first} =
             Catalog.new([
               manifest("tests/schemas/revision", :schema, Jido.Joi.object(%{a: Jido.Joi.string()}))
             ])

    assert {:ok, second} =
             Catalog.new([
               manifest("tests/schemas/revision", :schema, Jido.Joi.object(%{b: Jido.Joi.integer()}))
             ])

    refute Catalog.revision(first) == Catalog.revision(second)
  end

  test "catalog revision includes public display metadata" do
    first = manifest("tests/schemas/revision", :schema, Jido.Joi.object(%{value: Jido.Joi.string()}))
    second = %{first | name: "Changed name"}

    assert {:ok, first_catalog} = Catalog.new([first])
    assert {:ok, second_catalog} = Catalog.new([second])
    refute Catalog.revision(first_catalog) == Catalog.revision(second_catalog)
  end

  test "rejects invalid core manifest targets" do
    assert {:error, {:invalid_catalog_manifest, __MODULE__, {:invalid_catalog_entry, :kind, true}}} =
             Manifest.new(
               __MODULE__,
               :jido,
               %{id: "tests/invalid-kind", kind: true, vsn: 1, target: :name}
             )

    assert {:error, {:invalid_catalog_manifest, __MODULE__, {:invalid_catalog_entry, :target, _}}} =
             Manifest.new(
               __MODULE__,
               :jido,
               %{id: "tests/atoms/invalid", kind: :atom, vsn: 1, target: "name"}
             )

    assert {:error, {:invalid_catalog_manifest, __MODULE__, {:invalid_catalog_entry, :target, _}}} =
             Manifest.new(
               __MODULE__,
               :jido,
               %{id: "tests/schemas/invalid", kind: :schema, vsn: 1, target: self()}
             )
  end

  test "rejects duplicate stable IDs without replacing the current catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    catalog = Discovery.catalog()

    assert {:error, {:catalog_conflict, :reference, {"tests/actions/alpha", 2}}} =
             Discovery.refresh(
               applications: [],
               modules: [{AlphaAction, :jido}, {DuplicateAction, :jido}]
             )

    assert Discovery.catalog() == catalog
  end

  test "rejects a failed module scan without replacing the current catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    catalog = Discovery.catalog()

    assert {:error, {:invalid_catalog_manifest, InvalidManifest, _reason}} =
             Discovery.refresh(
               applications: [],
               modules: [{BetaAction, :jido}, {InvalidManifest, :jido}]
             )

    assert Discovery.catalog() == catalog
  end

  test "uses Catalog configuration and initializes synchronously" do
    Application.put_env(:jido, Jido.Catalog.Discovery,
      applications: [],
      modules: [{BetaAction, :jido}, {AlphaFlow, :jido}]
    )

    assert :ok = Discovery.initialize(modules: [{AlphaAction, :jido}])
    assert Enum.map(Discovery.list(:action), & &1.target) == [AlphaAction, BetaAction]
    assert Enum.map(Discovery.list(:flow), & &1.target) == [AlphaFlow]
  end

  test "provides a temporary Task child specification" do
    opts = [applications: [], modules: [{AlphaAction, :jido}]]

    assert %{
             id: Jido.Catalog.Discovery,
             start: {Task, :start_link, [initializer]},
             restart: :temporary,
             type: :worker
           } = Discovery.child_spec(opts)

    assert is_function(initializer, 0)
  end

  test "retains the latest asynchronous scan failure" do
    :persistent_term.erase({:jido, :catalog_snapshot})

    assert %{
             start: {Task, :start_link, [initializer]}
           } = Discovery.child_spec(applications: :bad)

    assert capture_log(initializer) =~ "Jido Catalog Discovery did not refresh"
    refute Discovery.ready?()

    error = assert_raise Jido.Codec.Error.InternalError, &Discovery.catalog/0
    assert error.code == :catalog_initialization_failed
    assert error.details == %{reason: {:invalid_applications, :bad}}

    assert %{start: {Task, :start_link, [retry]}} =
             Discovery.child_spec(applications: [], modules: :bad)

    assert capture_log(retry) =~ "Jido Catalog Discovery did not refresh"

    error = assert_raise Jido.Codec.Error.InternalError, &Discovery.catalog/0
    assert error.details == %{reason: {:invalid_modules, :bad}}
  end

  test "an asynchronous scan failure does not replace a valid Catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    catalog = Discovery.catalog()

    assert %{start: {Task, :start_link, [initializer]}} =
             Discovery.child_spec(applications: :bad)

    assert capture_log(initializer) =~ "Jido Catalog Discovery did not refresh"
    assert Discovery.catalog() == catalog
  end

  test "fails before initialization and rejects invalid scan options" do
    :persistent_term.erase({:jido, :catalog_snapshot})
    refute Discovery.ready?()

    for operation <- [
          &Discovery.catalog/0,
          &Discovery.codec_index/0,
          &Discovery.list/0,
          fn -> Discovery.get("missing", 1) end,
          fn -> Discovery.get_by_target(:atom, :missing) end
        ] do
      assert_raise Jido.Codec.Error.InternalError,
                   "Catalog is not initialized",
                   operation
    end

    assert {:error, {:invalid_applications, :bad}} = Discovery.refresh(applications: :bad)
    assert {:error, {:invalid_modules, :bad}} = Discovery.refresh(applications: [], modules: :bad)

    missing = Module.concat(__MODULE__, "Missing")

    assert {:error, {:module_not_loaded, :nofile}} =
             Discovery.refresh(applications: [], modules: [{missing, :jido}])

    assert {:error, {:invalid_discovery_options, [:unknown]}} =
             Discovery.refresh(applications: [], unknown: true)

    Application.put_env(:jido, Jido.Catalog.Discovery, :bad)
    assert {:error, {:invalid_discovery_config, :bad}} = Discovery.refresh()

    Application.put_env(:jido, Jido.Catalog.Discovery, unknown: true)

    assert {:error, {:invalid_discovery_config, {:unknown_options, [:unknown]}}} =
             Discovery.refresh()
  end

  test "a refresh before the first scan publishes survives the scan" do
    :persistent_term.erase({:jido, :catalog_snapshot})
    Process.register(self(), __MODULE__)

    scan =
      Task.async(fn ->
        Discovery.initialize(applications: [], modules: [{BlockingManifest, :jido}])
      end)

    assert_receive {:scan_started, scanner}, 5_000
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    send(scanner, :continue)
    assert :ok = Task.await(scan, 5_000)

    assert %{target: AlphaAction} = Discovery.get_by_target(:action, AlphaAction)
    assert Discovery.get("discovery_test/scanned", 1) == nil
  end

  test "a scan with no competing refresh replaces the published Catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    Process.register(self(), __MODULE__)

    scan =
      Task.async(fn ->
        Discovery.initialize(applications: [], modules: [{BlockingManifest, :jido}])
      end)

    assert_receive {:scan_started, scanner}, 5_000
    send(scanner, :continue)
    assert :ok = Task.await(scan, 5_000)

    assert %{target: :scanned} = Discovery.get("discovery_test/scanned", 1)
    assert Discovery.get_by_target(:action, AlphaAction) == nil
  end

  test "Codec decode returns Issues until a Catalog publishes" do
    catalog = Jido.Catalog.from_targets!(__MODULE__, :jido, %{})
    document = %{"type" => "jido.flow", "vsn" => 2}

    assert_publication_issue = fn code ->
      for opts <- [[], [catalog: catalog]],
          result <- [
            Jido.Codec.decode(document, opts),
            Jido.Codec.decode_json(JSON.encode!(document), opts),
            Jido.Codec.decode(%{"type" => "jido.flow"}, opts)
          ] do
        assert {:error, [%Jido.Codec.Issue{code: ^code, path: []}]} = result
      end
    end

    :persistent_term.erase({:jido, :catalog_snapshot})
    assert_publication_issue.(:catalog_not_initialized)

    :persistent_term.put({:jido, :catalog_snapshot}, {:error, :scan_failed})
    assert_publication_issue.(:catalog_initialization_failed)
  end

  test "the default startup scan includes all loaded applications" do
    Application.delete_env(:jido, Jido.Catalog.Discovery)

    assert :ok = Discovery.initialize()
    codecs = Discovery.codec_index()
    assert Index.codec(codecs, "jido.flow", 2) == {:ok, Jido.Flow.Codec}
  end

  defp manifest(id, kind, target) do
    Entry.new!(%{
      id: id,
      kind: kind,
      vsn: 1,
      target: target,
      provider: Vocabulary,
      name: nil,
      description: nil,
      application: :jido
    })
  end
end
