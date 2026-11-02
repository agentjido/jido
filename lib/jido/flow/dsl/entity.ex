defmodule Jido.Flow.DSL.Entity do
  @moduledoc false

  @source [__source__: [type: :map, default: %{}]]
  @node_fields @source ++
                 [
                   needs: [
                     type: {:wrap_list, :string},
                     default: [],
                     doc: "Explicit control dependencies."
                   ],
                   meta: [
                     type: {:map, :any, :any},
                     default: %{},
                     doc: "Non-semantic node metadata."
                   ]
                 ]

  @doc false
  defmacro __using__(options) do
    quote do
      @jido_dsl_entity Jido.Flow.DSL.Entity.build(__MODULE__, unquote(options))
      @before_compile Jido.Flow.DSL.Entity

      @doc false
      @spec entity() :: %Spark.Dsl.Entity{}
      def entity, do: @jido_dsl_entity
    end
  end

  @doc false
  @spec build(module(), keyword()) :: %Spark.Dsl.Entity{}
  def build(module, options) do
    {node?, options} = Keyword.pop(options, :node?, false)
    fields = if node?, do: @node_fields, else: @source
    schema = Keyword.fetch!(options, :schema) ++ fields
    struct!(Spark.Dsl.Entity, Keyword.merge(options, target: module, schema: schema))
  end

  @doc false
  defmacro __before_compile__(env) do
    entity = Module.get_attribute(env.module, :jido_dsl_entity)

    children =
      Enum.map(entity.entities, fn {key, _entities} ->
        {key, if(key in entity.singleton_entity_keys, do: nil, else: [])}
      end)

    fields =
      Enum.map(entity.schema, fn {key, options} -> {key, Keyword.get(options, :default)} end) ++
        children ++ [__identifier__: nil, __spark_metadata__: nil]

    types =
      Enum.map(fields, fn {key, default} ->
        type =
          cond do
            key in [:__source__, :meta] -> quote(do: map())
            default == [] -> quote(do: list())
            true -> quote(do: term())
          end

        {key, type}
      end)

    type = {:%, [], [{:__MODULE__, [], nil}, {:%{}, [], types}]}

    quote do
      defstruct unquote(Macro.escape(fields))
      @type t :: unquote(type)
    end
  end
end
