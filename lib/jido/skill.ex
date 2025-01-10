defmodule Jido.Skill do
  @moduledoc """
  Defines the core behavior and structure for Jido Skills.

  Skills are the fundamental building blocks of agent capabilities, providing:
  - Signal routing and handling
  - State management
  - Process supervision
  - Configuration management
  """

  alias Jido.Signal
  alias Jido.Error
  alias Jido.Runner.Result
  require OK
  use TypedStruct

  # Core skill structure
  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()], default: [])
    field(:vsn, String.t())
    field(:schema_key, atom())
    field(:signals, map())
    field(:config, map())
  end

  # Configuration schema validation
  @skill_config_schema NimbleOptions.new!(
                         name: [
                           type: {:custom, Jido.Util, :validate_name, []},
                           required: true,
                           doc:
                             "The name of the Skill. Must contain only letters, numbers, and underscores."
                         ],
                         description: [
                           type: :string,
                           required: false,
                           doc: "A description of what the Skill does."
                         ],
                         category: [
                           type: :string,
                           required: false,
                           doc: "The category of the Skill."
                         ],
                         tags: [
                           type: {:list, :string},
                           default: [],
                           doc: "A list of tags associated with the Skill."
                         ],
                         vsn: [
                           type: :string,
                           required: false,
                           doc: "The version of the Skill."
                         ],
                         schema_key: [
                           type: :atom,
                           required: true,
                           doc: "Atom key for state namespace isolation"
                         ],
                         signals: [
                           type: :map,
                           required: true,
                           doc: "Input/output signal patterns",
                           keys: [
                             input: [type: {:list, :string}, default: []],
                             output: [type: {:list, :string}, default: []]
                           ]
                         ],
                         config: [
                           type: :map,
                           required: false,
                           doc: "Configuration schema"
                         ]
                       )

  @doc """
  Implements the skill behavior and configuration validation.
  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@skill_config_schema)

    quote location: :keep do
      @behaviour Jido.Skill
      alias Jido.Skill
      alias Jido.Runner.Result
      alias Jido.Signal
      require OK

      # Validate configuration at compile time
      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          # Define metadata accessors
          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def schema_key, do: @validated_opts[:schema_key]
          def signals, do: @validated_opts[:signals]
          def config_schema, do: @validated_opts[:config]

          # Serialize metadata to JSON format
          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              schema_key: @validated_opts[:schema_key],
              signals: @validated_opts[:signals],
              config_schema: @validated_opts[:config]
            }
          end

          def __skill_metadata__ do
            to_json()
          end

          # Default implementations
          def initial_state, do: %{}
          def child_spec(_config), do: []
          def router, do: []

          def handle_result(%Result{status: :ok} = result, _path) do
            [
              %Signal{
                id: UUID.uuid4(),
                source: "replace_agent_id",
                type: "#{name()}.result",
                data: result.result_state
              }
            ]
          end

          def handle_result(%Result{status: :error} = result, _path) do
            [
              %Signal{
                id: UUID.uuid4(),
                source: "replace_agent_id",
                type: "#{name()}.error",
                data: %{
                  error: result.error
                }
              }
            ]
          end

          defoverridable initial_state: 0,
                         child_spec: 1,
                         router: 0,
                         handle_result: 2

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Skill", __MODULE__)

          raise CompileError,
            description: message,
            file: __ENV__.file,
            line: __ENV__.line
      end
    end
  end

  # Behaviour callbacks
  @callback initial_state() :: map()
  @callback child_spec(config :: map()) :: Supervisor.child_spec() | [Supervisor.child_spec()]
  @callback router() :: [map()]
  @callback handle_result(Result.t(), String.t()) :: [Signal.t()]

  @doc """
  Skills should be defined at compile time, not runtime.
  """
  @spec new() :: {:error, Error.t()}
  @spec new(map() | keyword()) :: {:error, Error.t()}
  def new, do: new(%{})

  def new(_map_or_kwlist) do
    "Skills should not be defined at runtime"
    |> Error.config_error()
    |> OK.failure()
  end

  @doc """
  Validates a skill's configuration against its schema.
  """
  @spec validate_config(module(), map()) :: {:ok, map()} | {:error, Error.t()}
  def validate_config(skill_module, config) do
    with {:ok, schema} <- get_config_schema(skill_module),
         {:ok, validated} <- NimbleOptions.validate(config, schema) do
      {:ok, validated}
    end
  end

  @doc """
  Gets a skill's configuration schema.
  """
  @spec get_config_schema(module()) :: {:ok, map()} | {:error, Error.t()}
  def get_config_schema(skill_module) do
    case function_exported?(skill_module, :config_schema, 0) do
      true ->
        {:ok, skill_module.config_schema()}

      false ->
        {:error, Error.config_error("Skill has no config schema")}
    end
  end

  @doc """
  Validates a signal against a skill's defined patterns.
  """
  @spec validate_signal(Signal.t(), map()) :: :ok | {:error, Error.t()}
  def validate_signal(%Signal{} = signal, patterns) do
    cond do
      match_any_pattern?(signal.type, patterns.input) ->
        :ok

      match_any_pattern?(signal.type, patterns.output) ->
        :ok

      true ->
        {:error, Error.validation_error("Signal type does not match any patterns")}
    end
  end

  # Private helpers
  defp match_any_pattern?(signal_type, patterns) do
    Enum.any?(patterns, &pattern_match?(signal_type, &1))
  end

  defp pattern_match?(signal_type, pattern) do
    regex = pattern_to_regex(pattern)
    String.match?(signal_type, regex)
  end

  defp pattern_to_regex(pattern) do
    pattern
    |> String.replace(".", "\\.")
    |> String.replace("*", ".*")
    |> then(&"^#{&1}$")
    |> Regex.compile!()
  end
end
