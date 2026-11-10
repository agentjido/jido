defmodule Jido.Catalog.DiscoveryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Catalog
  alias Jido.Catalog.{Discovery, Entry}
  alias Jido.Codec.Index

  defmodule AlphaAction do
    use Jido.Action,
      id: "tests/actions/alpha",
      vsn: 2,
      name: "alpha_action"

    @impl true
    def run(_params, _context), do: raise("discovery must not run Actions")
  end

  defmodule BetaAction do
    use Jido.Action,
      id: "tests/actions/beta",
      name: "beta_action"

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
          vsn: 1,
          target: :name,
          name: "name"
        },
        %{
          id: "tests/schemas/name",
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
        vsn: 1,
        target: :bare
      }
    end
  end

  defmodule BlockingManifest do
    def __jido_catalog_manifest__ do
      send(Jido.Catalog.DiscoveryTest, {:scan_started, self()})

      receive do
        :continue -> [%{id: "discovery_test/scanned", vsn: 1, target: :scanned}]
      end
    end
  end

  defmodule InvalidManifest do
    def __jido_catalog_manifest__, do: %{}
  end

  setup do
    catalog = :persistent_term.get({:jido, :catalog}, :not_ready)
    config = Application.get_env(:jido, Jido.Catalog.Discovery)

    on_exit(fn ->
      if catalog == :not_ready,
        do: :persistent_term.erase({:jido, :catalog}),
        else: :persistent_term.put({:jido, :catalog}, catalog)

      if config == nil,
        do: Application.delete_env(:jido, Jido.Catalog.Discovery),
        else: Application.put_env(:jido, Jido.Catalog.Discovery, config)
    end)

    :ok
  end

  test "declarations register modules and named schemas without a second setup step" do
    assert :ok =
             Discovery.refresh(
               applications: [],
               modules: [{AlphaAction, :jido}, {AlphaFlow, :jido}, {Jido.Flow.Codec, :jido}, {Vocabulary, :jido}]
             )

    catalog = Discovery.catalog()
    assert Discovery.ready?()
    assert %Entry{target: AlphaAction, vsn: 2} = Discovery.get("tests/actions/alpha", 2)
    assert {:ok, schema} = Catalog.resolve(catalog, {"#{AlphaAction}/schema", 1})
    assert schema == AlphaAction.schema()
    assert Index.codec(Discovery.codec_index(), "jido.flow", 2) == {:ok, Jido.Flow.Codec}
    assert {:ok, :name} = Catalog.resolve(catalog, {"tests/atoms/name", 1})
  end

  test "failed refresh keeps the last valid Catalog and identifies duplicate sources" do
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    catalog = Discovery.catalog()

    assert {:error, {:catalog_conflict, {"tests/actions/alpha", 2}, sources}} =
             Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}, {DuplicateAction, :jido}])

    assert Enum.sort(sources) == Enum.sort([{AlphaAction, :jido}, {DuplicateAction, :jido}])
    assert Discovery.catalog() == catalog

    assert {:error, {:invalid_catalog_manifest, InvalidManifest, _}} =
             Discovery.refresh(applications: [], modules: [{InvalidManifest, :jido}])

    assert Discovery.catalog() == catalog
  end

  test "startup is a temporary asynchronous Task and build failure is observable" do
    :persistent_term.erase({:jido, :catalog})
    assert %{restart: :temporary, start: {Task, :start_link, [initializer]}} = Discovery.child_spec(applications: :bad)
    assert capture_log(initializer) =~ "did not refresh"
    refute Discovery.ready?()
    error = assert_raise Jido.Codec.Error.InternalError, &Discovery.catalog/0
    assert error.code == :catalog_build_failed
    assert error.details == %{reason: {:invalid_applications, :bad}}
  end

  test "definitions added after startup require explicit refresh" do
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    assert Discovery.get("tests/actions/beta", 1) == nil
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}, {BetaAction, :jido}])
    assert Discovery.get("tests/actions/beta", 1).target == BetaAction
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
    :persistent_term.erase({:jido, :catalog})
    refute Discovery.ready?()

    for operation <- [
          &Discovery.catalog/0,
          &Discovery.codec_index/0,
          &Discovery.list/0,
          fn -> Discovery.get("missing", 1) end,
          fn -> Discovery.get_by_target(:missing) end
        ] do
      assert_raise Jido.Codec.Error.InternalError,
                   "Catalog is not ready",
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
    :persistent_term.erase({:jido, :catalog})
    Process.register(self(), __MODULE__)

    scan =
      Task.async(fn ->
        Discovery.initialize(applications: [], modules: [{BlockingManifest, :jido}])
      end)

    assert_receive {:scan_started, scanner}, 5_000
    assert :ok = Discovery.refresh(applications: [], modules: [{AlphaAction, :jido}])
    send(scanner, :continue)
    assert :ok = Task.await(scan, 5_000)

    assert %{target: AlphaAction} = Discovery.get_by_target(AlphaAction)
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
    assert Discovery.get_by_target(AlphaAction) == nil
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

    :persistent_term.erase({:jido, :catalog})
    assert_publication_issue.(:catalog_not_ready)

    :persistent_term.put({:jido, :catalog}, {:error, :scan_failed})
    assert_publication_issue.(:catalog_build_failed)
  end
end
