defmodule Jido.Examples.DefinitionRevision do
  @moduledoc """
  Installs two revisions of one isolated cart module to model a deployment.
  Agent `vsn` is declared as static module data. Only the probe Cart module is
  replaced.
  """
  def install(revision) do
    module = __MODULE__.Cart
    unload()

    quoted =
      quote do
        defmodule unquote(module) do
          use Jido.Agent, name: "research_versioned_cart", vsn: unquote(revision)

          agent do
            schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
          end
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
