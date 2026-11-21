defmodule Jido.Catalog.HydrationTest do
  use ExUnit.Case, async: false
  alias Jido.Catalog
  alias Jido.Catalog.Discovery
  alias Jido.Codec
  alias Jido.Codec.{Issue, Reference}

  defmodule Before do
    def __jido_catalog_manifest__, do: %{id: "tests/current", target: :before}
  end

  defmodule After do
    def __jido_catalog_manifest__, do: %{id: "tests/current", target: :after}
  end

  defmodule Result do
    defstruct [:first, :second]
  end

  defmodule Reader do
    @behaviour Jido.Codec.Contract
    def type, do: "tests.current"
    def version, do: 1
    def target, do: nil

    def decode(document, catalog) do
      reference = document["reference"]

      with {:ok, first} <- Reference.decode(catalog, reference),
           :ok <- Discovery.refresh(applications: [], modules: [{After, :jido}]),
           {:ok, second} <- Reference.decode(catalog, reference) do
        {:ok, %Result{first: first, second: second}}
      end
    end
  end

  setup do
    previous = :persistent_term.get({:jido, :catalog}, :not_ready)

    on_exit(fn ->
      if previous == :not_ready,
        do: :persistent_term.erase({:jido, :catalog}),
        else: :persistent_term.put({:jido, :catalog}, previous)
    end)

    :ok
  end

  test "each normal reference lookup uses the current Catalog" do
    assert :ok = Discovery.refresh(applications: [], modules: [{Before, :jido}])
    assert {:ok, %Result{first: :before, second: :after}} = Codec.decode(document(), codec: Reader)
  end

  test "an explicit Catalog takes precedence, including before publication" do
    :persistent_term.erase({:jido, :catalog})
    catalog = Catalog.from_targets!(__MODULE__, :jido, %{{"tests/current", 1} => :explicit})

    assert {:ok, %Result{first: :explicit, second: :explicit}} =
             Codec.decode(document(), codec: Reader, catalog: catalog)
  end

  test "readiness, build failure, and missing references are separate failures" do
    :persistent_term.erase({:jido, :catalog})
    assert {:error, [%Issue{code: :catalog_not_ready}]} = Codec.decode(document(), codec: Reader)
    :persistent_term.put({:jido, :catalog}, {:error, :failed})
    assert {:error, [%Issue{code: :catalog_build_failed}]} = Codec.decode(document(), codec: Reader)
    catalog = Catalog.new!([])

    assert {:error, %Catalog.Error{message: "unknown Catalog reference"}} =
             Reference.decode(catalog, document()["reference"])
  end

  defp document, do: %{"type" => "tests.current", "vsn" => 1, "reference" => %{"id" => "tests/current", "vsn" => 1}}
end
