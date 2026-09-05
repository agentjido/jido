defmodule Jido.Examples.DefinitionRevision do
  @moduledoc """
  Installs two revisions of one isolated cart module to model a deployment.
  Revision is declared in metadata and a module function because core has no
  definition_revision option. Only the probe Cart module is replaced.
  """
  def install(revision) do
    module = __MODULE__.Cart
    unload()

    quoted =
      quote do
        defmodule unquote(module) do
          use Jido.Agent, name: "research_versioned_cart"

          agent do
            metadata %{definition_revision: unquote(revision)}
            schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
          end

          def definition_revision, do: unquote(revision)
        end
      end

    Code.compile_quoted(quoted)
    module
  end

  def unload do
    :code.purge(__MODULE__.Cart)
    :code.delete(__MODULE__.Cart)
    :ok
  end
end
