defmodule Jido.Examples.Plugins.DSL.Threshold do
  @moduledoc "One named threshold in the Plugin DSL."
  defstruct [:name, :at, :__spark_metadata__]
end

defmodule Jido.Examples.Plugins.DSL.Thresholds do
  @moduledoc "Adds Agent syntax and reduces a field from its validated configuration."
  alias Spark.Dsl.Extension, as: DSL

  @threshold %Spark.Dsl.Entity{
    name: :threshold,
    target: Jido.Examples.Plugins.DSL.Threshold,
    args: [:name],
    schema: [name: [type: :atom, required: true], at: [type: :pos_integer, required: true]]
  }
  @section %Spark.Dsl.Section{
    name: :thresholds,
    schema: [on: [type: :string, required: true]],
    entities: [@threshold]
  }
  use Jido.Plugin, id: "examples.thresholds", vsn: 1, sections: [@section]

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    entries = DSL.get_entities(dsl, [:thresholds])

    cond do
      config != %{} and entries != [] ->
        {:error, :choose_dsl_or_config}

      config != %{} ->
        {:ok, config}

      true ->
        {:ok,
         %{
           on: DSL.get_opt(dsl, [:thresholds], :on),
           thresholds: Enum.map(entries, &Map.take(&1, [:name, :at]))
         }}
    end
  end

  @config_schema Zoi.object(
                   %{
                     on: Zoi.string() |> Zoi.min(1),
                     thresholds:
                       Zoi.list(
                         Zoi.object(
                           %{
                             name: Zoi.atom(),
                             at: Zoi.integer() |> Zoi.min(1)
                           },
                           unrecognized_keys: :error
                         )
                       )
                   },
                   unrecognized_keys: :error
                 )

  @impl Jido.Agent.Extension
  def normalize(data) do
    with {:ok, data} <- Zoi.parse(@config_schema, data) do
      names = Enum.map(data.thresholds, & &1.name)
      if names == Enum.uniq(names), do: {:ok, data}, else: {:error, :duplicate_threshold_names}
    end
  end

  @impl Jido.Agent.Extension
  def verify(data, definition) do
    if Enum.any?(definition.routes, &(&1.path == data.on)),
      do: :ok,
      else: {:error, :threshold_signal_needs_an_exact_route}
  end

  @impl Jido.Plugin
  def state_spec(_opts), do: {:reached, Zoi.list(Zoi.atom()) |> Zoi.default([])}

  @impl Jido.Plugin
  def reduce(reduction, opts) do
    if reduction.signal.type == opts[:on] do
      reached =
        for %{name: name, at: at} <- opts[:thresholds],
            reduction.state.count >= at,
            name not in reduction.plugin_state,
            do: name

      {:ok, reduction.plugin_state ++ reached}
    else
      {:ok, reduction.plugin_state}
    end
  end
end
