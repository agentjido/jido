defmodule Jido.Agent.DSL.ExtensionTest.FakeBinding do
  @moduledoc false
end

defmodule Jido.Agent.DSL.ExtensionTest.FakeExtension.Data do
  @moduledoc false

  @enforce_keys [:binding]
  defstruct [:binding, mode: :observe, limit: 1]
end

defmodule Jido.Agent.DSL.ExtensionTest.FakeExtension.DSL do
  @moduledoc false

  @typed_extension %Spark.Dsl.Section{
    name: :typed_extension,
    schema: [
      binding_module: [type: :atom, required: true],
      mode: [type: {:one_of, [:observe, :enforce]}, default: :observe],
      limit: [type: :pos_integer, default: 1]
    ]
  }

  use Spark.Dsl.Extension, sections: [@typed_extension]

  def agent_extension, do: Jido.Agent.DSL.ExtensionTest.FakeExtension

  def lower(resource) do
    {:ok,
     %{
       data: %{
         binding: Spark.Dsl.Extension.get_opt(resource, [:typed_extension], :binding_module),
         mode: Spark.Dsl.Extension.get_opt(resource, [:typed_extension], :mode),
         limit: Spark.Dsl.Extension.get_opt(resource, [:typed_extension], :limit)
       },
       metadata: %{owner: "typed-extension"}
     }}
  end
end

defmodule Jido.Agent.DSL.ExtensionTest.FakeExtension do
  @moduledoc false

  @behaviour Jido.Agent.Extension

  alias Jido.Agent.DSL.ExtensionTest.FakeExtension.Data
  alias Jido.Agent.Registry
  alias Jido.Error

  @impl true
  def normalize(%Data{} = data), do: {:ok, data}

  def normalize(attrs) when is_map(attrs) do
    if Map.keys(attrs) -- [:binding, :limit, :mode] == [] do
      {:ok,
       struct!(Data, %{
         binding: Map.get(attrs, :binding),
         limit: Map.get(attrs, :limit, 1),
         mode: Map.get(attrs, :mode, :observe)
       })}
    else
      {:error, Error.validation_error("unknown fake extension field")}
    end
  end

  def normalize(_value),
    do: {:error, Error.validation_error("fake extension data must be a map")}

  @impl true
  def validate(%Data{binding: binding, mode: mode, limit: limit})
      when is_atom(binding) and mode in [:observe, :enforce] and is_integer(limit) and limit > 0,
      do: :ok

  def validate(_data), do: {:error, Error.validation_error("invalid fake extension data")}

  @impl true
  def validate_executable(%Data{binding: binding}) do
    if Code.ensure_loaded?(binding),
      do: :ok,
      else: {:error, Error.validation_error("fake binding is not loaded")}
  end

  @impl true
  def encode(%Data{} = data, %Registry{} = registry) do
    with {:ok, binding} <-
           Registry.identifier(registry, {:extension, __MODULE__, :binding}, data.binding) do
      {:ok,
       %{
         "binding" => binding,
         "limit" => data.limit,
         "mode" => Atom.to_string(data.mode)
       }}
    end
  end

  @impl true
  def decode(document, %Registry{} = registry) when is_map(document) do
    Process.put(:fake_extension_decode_called, true)

    with [] <- Map.keys(document) -- ["binding", "limit", "mode"],
         {:ok, binding_id} <- Map.fetch(document, "binding"),
         {:ok, binding} <-
           Registry.resolve(registry, binding_id, {:extension, __MODULE__, :binding}),
         {:ok, mode} <- decode_mode(Map.get(document, "mode")),
         limit when is_integer(limit) and limit > 0 <- Map.get(document, "limit") do
      {:ok, %Data{binding: binding, mode: mode, limit: limit}}
    else
      _reason -> {:error, Error.validation_error("invalid fake extension document")}
    end
  end

  def decode(_document, _registry),
    do: {:error, Error.validation_error("invalid fake extension document")}

  @impl true
  def registry_values(%Data{binding: binding}), do: [{:binding, binding}]

  @impl true
  def compile(%Data{} = data, metadata), do: {:ok, %{data: data, metadata: metadata}}

  @impl true
  def spark_extension, do: Jido.Agent.DSL.ExtensionTest.FakeExtension.DSL

  defp decode_mode("observe"), do: {:ok, :observe}
  defp decode_mode("enforce"), do: {:ok, :enforce}
  defp decode_mode(_mode), do: :error
end
