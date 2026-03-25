defmodule Jido.Sensor.Spec do
  @moduledoc """
  The normalized representation of a sensor specification.

  Contains all metadata needed to configure and run a sensor,
  including the module, name, description, configuration, and schema.

  ## Fields

  - `module` - The sensor module (required)
  - `name` - Sensor name (required)
  - `description` - Optional sensor description
  - `config` - Configuration map for the sensor (default: %{})
  - `schema` - Optional Zoi schema for introspection

  ## Examples

      Sensor.Spec.new!(%{module: MySensor, name: "my_sensor"})
      # => %Sensor.Spec{module: MySensor, name: "my_sensor", config: %{}}

      Sensor.Spec.new(%{module: MySensor, name: "my_sensor", config: %{interval: 1000}})
      # => {:ok, %Sensor.Spec{module: MySensor, name: "my_sensor", config: %{interval: 1000}}}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              module: Zoi.atom(description: "The sensor module"),
              name: Zoi.string(description: "Sensor name"),
              description: Zoi.string(description: "Sensor description") |> Zoi.optional(),
              config: Zoi.map(description: "Configuration for the sensor") |> Zoi.default(%{}),
              schema: Zoi.any(description: "Zoi schema for introspection") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Sensor.Spec."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new Sensor.Spec from a map of attributes.

  Returns `{:ok, spec}` or `{:error, reason}`.

  ## Examples

      Sensor.Spec.new(%{module: MySensor, name: "my_sensor"})
      # => {:ok, %Sensor.Spec{module: MySensor, name: "my_sensor", config: %{}}}

      Sensor.Spec.new(%{name: "missing_module"})
      # => {:error, validation_errors}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  def new(_), do: {:error, Jido.Error.validation_error("Sensor.Spec requires a map")}

  @doc """
  Creates a new Sensor.Spec from a map, raising on error.

  ## Examples

      Sensor.Spec.new!(%{module: MySensor, name: "my_sensor"})
      # => %Sensor.Spec{module: MySensor, name: "my_sensor", config: %{}}
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, spec} ->
        spec

      {:error, reason} ->
        raise Jido.Error.validation_error("Invalid Sensor.Spec", details: reason)
    end
  end
end
