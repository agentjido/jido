defmodule Jido.Examples.PackageCatalog.NormalizeName do
  @moduledoc "A package Action that contributes itself and its schemas."

  use Jido.Action,
    id: "examples/catalog/normalize-name",
    vsn: 1,
    name: "example_catalog_normalize_name",
    schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{name: Jido.Joi.string()})

  @impl true
  def run(%{name: name}, _context), do: {:ok, %{name: name |> String.trim() |> String.downcase()}}
end

defmodule Jido.Examples.PackageCatalog.Vocabulary do
  @moduledoc "A package contribution for a portable named value."

  def __jido_catalog_manifest__ do
    %{id: "examples/catalog/atoms/display-name", vsn: 1, target: :display_name}
  end
end

defmodule Jido.Examples.PackageCatalog do
  @moduledoc "Publishes and resolves one explicit package inventory."

  alias Jido.Catalog.Discovery
  alias Jido.Examples.PackageCatalog.{NormalizeName, Vocabulary}

  def refresh do
    Discovery.refresh(
      applications: [],
      modules: [{NormalizeName, :jido}, {Vocabulary, :jido}]
    )
  end

  def resolve_action, do: Discovery.get("examples/catalog/normalize-name", 1)
  def resolve_value, do: Discovery.get("examples/catalog/atoms/display-name", 1)
end
