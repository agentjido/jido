defmodule Jido.Agent.Options do
  @moduledoc """
  Prepares public options for macros that build on `Jido.Agent`.

  A wrapper macro can prepare its options, add required Plugins, and pass the
  result to `use Jido.Agent`. Plugin declarations stay in the public
  `:plugins` option. `Jido.Agent` validates and lowers them when it compiles the
  Agent DSL.

      defmacro __using__(quoted_options) do
        options =
          quoted_options
          |> Jido.Agent.Options.prepare!(__CALLER__)
          |> Jido.Agent.Options.prepend_plugin(MyApp.RequiredPlugin)

        quote do
          use Jido.Agent, unquote(Macro.escape(options))
        end
      end
  """

  alias Jido.Authoring.Registry

  @type t :: keyword()

  @doc """
  Evaluates public Agent options and resolves their authoring ID.

  The caller module name is the default `:id`. The returned keyword list keeps
  Plugin declarations in the public `:plugins` option. `use Jido.Agent`
  validates the complete option set.
  """
  @spec prepare!(Macro.t(), Macro.Env.t()) :: t()
  def prepare!(quoted_options, %Macro.Env{} = caller) do
    {options, _binding} = Code.eval_quoted(quoted_options, [], caller)

    options =
      options
      |> validate_keyword!()
      |> Keyword.put_new(:id, Atom.to_string(caller.module))

    case Registry.validate_identifier(options[:id]) do
      :ok -> options
      {:error, error} -> raise error
    end
  end

  @doc """
  Adds one required Plugin before the caller's Plugin declarations.

  If the caller already has the exact required declaration, this function does
  not add it again. Other repeated or configured declarations remain unchanged
  so normal Agent validation can report a conflict.
  """
  @spec prepend_plugin(t(), Jido.Plugin.declaration()) :: t()
  def prepend_plugin(options, plugin) do
    options = validate_keyword!(options)
    plugins = Keyword.get(options, :plugins, [])

    unless is_list(plugins), do: raise(ArgumentError, "Agent plugins must be a list")

    plugins = if plugin in plugins, do: plugins, else: [plugin | plugins]

    Keyword.delete(options, :plugins) ++ [plugins: plugins]
  end

  defp validate_keyword!(options) do
    unless Keyword.keyword?(options) and Enum.uniq(Keyword.keys(options)) == Keyword.keys(options),
      do: raise(ArgumentError, "Agent requires unique keyword options")

    options
  end
end
