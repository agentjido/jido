defmodule Jido.Plugin do
  @moduledoc """
  A declared capability for one `Jido.Agent` module.

  A Plugin can admit live command input, prepare pure command input, transform
  outbound Signals, own one portable Agent state key, own Directive types, and
  start one supervised runtime process. A Directive can reduce Plugin state
  without a runtime, or dispatch runtime work after commit. Each part is
  optional. A Plugin module can occur only once in one Agent definition. A
  runtime root, when supplied, must use `restart: :permanent`. It can supervise
  shorter-lived work below that root.

  Live admission runs before pure command preparation and routing. Outbound
  Signal transformation runs after correlation data is added and before
  delivery. These live callbacks run outside the Agent Server process and can
  use the Plugin runtime. Command preparation and state reduction stay pure and
  run before the Agent commit. Runtime Directive dispatch runs only after the
  commit. A runtime Plugin never receives the complete private server state.

  Directive dispatch does not require a Plugin process. A Plugin without
  `child_spec/1` receives `nil` as the runtime reference in `dispatch/4`. The
  Agent Server runs that callback in its supervised task with the same timeout,
  ordering, and failure rules as dispatch through a Plugin process. Declare a
  child only when the capability needs a connection, timer, or other live state.

  Message history belongs in the application's Agent schema. Actions return
  the complete next history with the rest of the Agent state. History needs no
  Plugin or Directive. `Jido.Thread` remains an optional application data value.

  Define a Plugin with `use Jido.Plugin`:

      defmodule MyApp.AuditPlugin do
        use Jido.Plugin

        @impl Jido.Plugin
        def prepare(command, _opts), do: {:ok, command}
      end

  Module options belong in the Agent Plugin declaration. `use Jido.Plugin`
  does not accept options.
  """

  alias Jido.Agent.Command
  alias Jido.Plugin.{DirectiveContext, Init, SignalContext, Spec}
  alias Jido.Error

  @type result :: {:ok, proposed_state :: map(), directives :: [struct()]} | {:error, term()}
  @type declaration :: module() | {module(), keyword()}
  @type state_spec :: :none | {atom(), Zoi.schema()}

  @doc "Defines one v3 Agent Plugin."
  defmacro __using__([]) do
    quote location: :keep do
      @behaviour Jido.Plugin

      @doc false
      def __jido_plugin__, do: :agent
    end
  end

  defmacro __using__(opts) do
    raise ArgumentError,
          "use Jido.Plugin does not accept options; put options in the Agent plugins declaration, got: #{Macro.to_string(opts)}"
  end

  @callback prepare(command :: Command.t(), opts :: keyword()) ::
              {:ok, Command.t()} | {:error, term()}
  @callback admit(runtime_ref :: term() | nil, command :: Command.t(), opts :: keyword()) ::
              {:ok, Command.t()} | {:error, term()}
  @callback prepare_dispatch(
              runtime_ref :: term() | nil,
              signal :: Jido.Signal.t(),
              context :: SignalContext.t(),
              opts :: keyword()
            ) :: {:ok, Jido.Signal.t()} | {:error, term()}
  @callback state_spec(opts :: keyword()) :: state_spec()
  @callback update_state(plugin_state :: term(), directives :: [struct()], opts :: keyword()) ::
              {:ok, plugin_state :: term()} | {:error, term()}
  @callback directives(opts :: keyword()) :: [module()]
  @callback validate_directive(directive :: struct(), opts :: keyword()) ::
              {:ok, struct()} | {:error, term()}
  @callback dispatch(
              runtime_ref :: term() | nil,
              directive :: struct(),
              context :: DirectiveContext.t(),
              opts :: keyword()
            ) :: :ok | {:error, term()}
  @callback await_ready(runtime_ref :: term(), opts :: keyword()) :: :ok | {:error, term()}

  @optional_callbacks prepare: 2,
                      admit: 3,
                      prepare_dispatch: 4,
                      state_spec: 1,
                      update_state: 3,
                      directives: 1,
                      validate_directive: 2,
                      dispatch: 4,
                      await_ready: 2

  @doc false
  @spec normalize_all([declaration()]) :: {:ok, [Spec.t()]} | {:error, Exception.t()}
  def normalize_all(declarations) when is_list(declarations) do
    with {:ok, specs} <- normalize_specs(declarations),
         :ok <- unique_modules(specs),
         :ok <- unique_state_keys(specs),
         :ok <- unique_directives(specs) do
      {:ok, specs}
    end
  end

  def normalize_all(value), do: invalid("Agent Plugins must be a list", %{plugins: value})

  @doc false
  @spec canonical_declarations([declaration()]) ::
          {:ok, [{module(), keyword()}]} | {:error, Exception.t()}
  def canonical_declarations(declarations) do
    with {:ok, specs} <- normalize_all(declarations) do
      {:ok, Enum.map(specs, &{&1.module, &1.options})}
    end
  end

  @doc false
  @spec compose_schema(Zoi.schema(), [declaration()]) ::
          {:ok, Zoi.schema()} | {:error, Exception.t()}
  def compose_schema(%Zoi.Types.Map{fields: fields} = domain_schema, declarations)
      when is_list(fields) do
    with {:ok, specs} <- normalize_all(declarations),
         :ok <- state_key_conflicts(fields, specs) do
      plugin_fields =
        Enum.reduce(specs, %{}, fn
          %Spec{state_key: nil}, fields -> fields
          %Spec{state_key: key, state_schema: schema}, fields -> Map.put(fields, key, schema)
        end)

      # Keep Zoi's field normalization without replacing the root refinements
      # and other metadata that must also validate Plugin composition.
      extended = Zoi.extend(domain_schema, plugin_fields)
      {:ok, %{domain_schema | fields: extended.fields}}
    end
  end

  def compose_schema(schema, _declarations) do
    invalid("Agent domain schema must be a field-based Zoi object", %{schema: schema})
  end

  @doc false
  def compose_schema!(domain_schema, declarations) do
    case compose_schema(domain_schema, declarations) do
      {:ok, schema} -> schema
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec validate_composed_schema(Zoi.schema(), [Spec.t()]) ::
          :ok | {:error, Exception.t()}
  def validate_composed_schema(%Zoi.Types.Map{fields: fields}, specs) when is_list(fields) do
    Enum.reduce_while(specs, :ok, fn
      %Spec{state_key: nil}, :ok ->
        {:cont, :ok}

      %Spec{module: module, state_key: key, state_schema: expected}, :ok ->
        case Keyword.fetch(fields, key) do
          {:ok, actual} ->
            if equivalent_field_schema?(actual, expected) do
              {:cont, :ok}
            else
              {:halt,
               invalid("Agent Plugin state schema does not match", %{
                 plugin: module,
                 state_key: key,
                 expected: expected,
                 actual: actual
               })}
            end

          :error ->
            {:halt,
             invalid("Agent Plugin state key is missing from the composed schema", %{
               plugin: module,
               state_key: key
             })}
        end
    end)
  end

  def validate_composed_schema(schema, _specs),
    do: invalid("Agent schema must be a field-based Zoi object", %{schema: schema})

  defp equivalent_field_schema?(%{meta: actual_meta} = actual, %{meta: expected_meta} = expected) do
    %{actual | meta: %{actual_meta | required: nil}} ==
      %{expected | meta: %{expected_meta | required: nil}}
  end

  defp equivalent_field_schema?(actual, expected), do: actual == expected

  @doc false
  @spec prepare(Command.t(), [declaration()]) ::
          {:ok, Command.t(), [Spec.t()]} | {:error, term()}
  def prepare(%Command{} = command, declarations) do
    with {:ok, command} <- Command.validate(command),
         {:ok, specs} <- normalize_all(declarations),
         {:ok, command} <- prepare_all(command, specs) do
      {:ok, command, specs}
    end
  end

  @doc false
  @spec prepare_specs(Command.t(), [Spec.t()]) ::
          {:ok, Command.t(), [Spec.t()]} | {:error, term()}
  def prepare_specs(%Command{} = command, specs) when is_list(specs) do
    with {:ok, command} <- Command.validate(command),
         {:ok, command} <- prepare_all(command, specs) do
      {:ok, command, specs}
    end
  end

  @doc false
  @spec admits?([Spec.t()]) :: boolean()
  def admits?(specs) when is_list(specs) do
    Enum.any?(specs, &function_exported?(&1.module, :admit, 3))
  end

  @doc false
  @spec admission_modules([Spec.t()]) :: [module()]
  def admission_modules(specs) when is_list(specs) do
    callback_modules(specs, :admit, 3)
  end

  @doc false
  @spec dispatch_modules([Spec.t()]) :: [module()]
  def dispatch_modules(specs) when is_list(specs) do
    callback_modules(specs, :prepare_dispatch, 4)
  end

  @doc false
  @spec admit(Command.t(), [Spec.t()], %{optional(module()) => term() | nil}) ::
          {:ok, Command.t()} | {:error, term()}
  def admit(%Command{} = command, specs, runtime_refs)
      when is_list(specs) and is_map(runtime_refs) do
    with {:ok, command} <- Command.validate(command) do
      Enum.reduce_while(specs, {:ok, command}, fn spec, {:ok, current} ->
        case admit_one(current, spec, Map.get(runtime_refs, spec.module)) do
          {:ok, admitted} -> {:cont, {:ok, admitted}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  @doc false
  @spec prepare_dispatch(
          Jido.Signal.t(),
          [Spec.t()],
          %{optional(module()) => term() | nil},
          SignalContext.t(),
          map()
        ) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def prepare_dispatch(%Jido.Signal{} = signal, specs, runtime_refs, context, agent_state)
      when is_list(specs) and is_map(runtime_refs) and is_map(agent_state) do
    specs
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, signal}, fn spec, {:ok, current} ->
      plugin_context = %{
        context
        | plugin_state: plugin_state(agent_state, spec.state_key)
      }

      case prepare_dispatch_one(
             current,
             spec,
             Map.get(runtime_refs, spec.module),
             plugin_context
           ) do
        {:ok, prepared} -> {:cont, {:ok, prepared}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  @spec protect_state(result(), map(), [Spec.t()]) :: result()
  def protect_state({:ok, state, _directives} = result, original_state, specs) do
    case changed_keys(original_state, state, state_keys(specs)) do
      [] ->
        result

      keys ->
        {:error,
         plugin_error("Agent executable changed Plugin-owned state", :core, %{keys: keys})}
    end
  end

  def protect_state(result, _original_state, _specs), do: result

  @doc false
  @spec update_state(result(), [Spec.t()]) :: result()
  def update_state(result, specs), do: apply_state_updates(result, specs)

  @doc false
  @spec child_specs(Init.t(), [declaration()]) ::
          {:ok, [Supervisor.child_spec()]} | {:error, Exception.t()}
  def child_specs(%Init{} = init, declarations) do
    with {:ok, specs} <- normalize_all(declarations) do
      child_specs_for(specs, fn spec ->
        %{init | module: spec.module, options: spec.options}
      end)
    end
  end

  @doc "Gets the current state owned by one Plugin runtime."
  @spec state(Init.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def state(%Init{agent_server: agent_server, module: module}, timeout \\ 5_000) do
    Jido.AgentServer.plugin_state(agent_server, module, timeout)
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end

  @doc false
  def state_keys(specs), do: specs |> Enum.map(& &1.state_key) |> Enum.reject(&is_nil/1)

  @doc false
  def directive_owner(specs, %{__struct__: directive_module}) do
    Enum.find(specs, &(directive_module in &1.directive_modules))
  end

  def directive_owner(_specs, _directive), do: nil

  @doc false
  def validate_directive(%Spec{} = spec, %{__struct__: directive_module} = directive) do
    safe_apply(
      spec.module,
      :validate_directive,
      [directive, spec.options],
      "Agent Plugin Directive validation failed"
    )
    |> case do
      {:ok, %{__struct__: ^directive_module} = validated} ->
        {:ok, validated}

      {:ok, %{__struct__: validated_module}} ->
        plugin_invalid(
          "Agent Plugin validate_directive/2 changed Directive type",
          spec.module,
          %{expected: directive_module, actual: validated_module}
        )

      {:error, _reason} = error ->
        error

      result ->
        plugin_invalid(
          "Agent Plugin validate_directive/2 returned an invalid result",
          spec.module,
          %{result: result}
        )
    end
  end

  @doc false
  def dispatch(%Spec{} = spec, runtime_ref, directive, %DirectiveContext{} = context) do
    safe_apply(
      spec.module,
      :dispatch,
      [runtime_ref, directive, context, spec.options],
      "Agent Plugin Directive dispatch failed"
    )
    |> case do
      :ok ->
        :ok

      {:error, _reason} = error ->
        error

      result ->
        plugin_invalid("Agent Plugin dispatch/4 returned an invalid result", spec.module, %{
          result: result
        })
    end
  end

  @doc false
  def await_ready(%Spec{runtime?: false}, _runtime_ref), do: :ok

  def await_ready(%Spec{} = spec, runtime_ref) do
    if function_exported?(spec.module, :await_ready, 2) do
      safe_apply(
        spec.module,
        :await_ready,
        [runtime_ref, spec.options],
        "Agent Plugin readiness check failed"
      )
      |> case do
        :ok ->
          :ok

        {:error, _reason} = error ->
          error

        result ->
          plugin_invalid(
            "Agent Plugin await_ready/2 returned an invalid result",
            spec.module,
            %{result: result}
          )
      end
    else
      :ok
    end
  end

  defp normalize_specs(declarations) do
    declarations
    |> Enum.reduce_while({:ok, []}, fn declaration, {:ok, specs} ->
      case normalize(declaration) do
        {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  defp normalize(module) when is_atom(module), do: build_spec(module, [])

  defp normalize({module, opts}) when is_atom(module) and is_list(opts) do
    if Keyword.keyword?(opts) do
      build_spec(module, opts)
    else
      invalid("Agent Plugin options must be a keyword list", %{
        plugin: module,
        options: opts
      })
    end
  end

  defp normalize(declaration),
    do: invalid("Invalid Agent Plugin declaration", %{plugin: declaration})

  defp build_spec(module, opts) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         :ok <- validate_plugin_contract(module),
         :ok <- plugin_has_capability(module),
         {:ok, {state_key, state_schema}} <- read_state_spec(module, opts),
         {:ok, directive_modules} <- read_directives(module, opts),
         :ok <- validate_directive_contract(module, directive_modules),
         :ok <- validate_state_update_contract(module, state_key) do
      {:ok,
       %Spec{
         module: module,
         options: opts,
         state_key: state_key,
         state_schema: state_schema,
         directive_modules: directive_modules,
         dispatch?: function_exported?(module, :dispatch, 4),
         runtime?: function_exported?(module, :child_spec, 1)
       }}
    else
      {:error, %_{} = error} ->
        {:error, error}

      {:error, reason} ->
        invalid("Agent Plugin could not be loaded", %{plugin: module, reason: reason})
    end
  end

  defp validate_plugin_contract(module) do
    behaviours =
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    marker =
      if function_exported?(module, :__jido_plugin__, 0) do
        safe_apply(module, :__jido_plugin__, [], "Agent Plugin marker failed")
      else
        :missing
      end

    cond do
      Jido.Plugin in behaviours and marker == :agent ->
        :ok

      match?({:error, _reason}, marker) ->
        marker

      true ->
        invalid("Agent Plugin must use Jido.Plugin", %{plugin: module})
    end
  end

  defp plugin_has_capability(module) do
    callbacks = [
      prepare: 2,
      admit: 3,
      prepare_dispatch: 4,
      state_spec: 1,
      update_state: 3,
      directives: 1,
      child_spec: 1
    ]

    if Enum.any?(callbacks, fn {name, arity} -> function_exported?(module, name, arity) end) do
      :ok
    else
      invalid("Agent Plugin defines no capability", %{plugin: module})
    end
  end

  defp read_state_spec(module, opts) do
    if function_exported?(module, :state_spec, 1) do
      safe_apply(module, :state_spec, [opts], "Agent Plugin state_spec/1 failed")
      |> validate_state_spec(module)
    else
      {:ok, {nil, nil}}
    end
  end

  defp validate_state_spec(:none, _module), do: {:ok, {nil, nil}}

  defp validate_state_spec({key, %{__struct__: _type} = schema}, module) when is_atom(key) do
    case Jido.Action.validate_static_data(schema) do
      :ok ->
        {:ok, {key, schema}}

      {:error, reason} ->
        invalid("Agent Plugin state schema must contain static data", %{
          plugin: module,
          state_key: key,
          reason: reason
        })
    end
  end

  defp validate_state_spec(value, module),
    do:
      invalid("Agent Plugin state_spec/1 returned an invalid value", %{
        plugin: module,
        value: value
      })

  defp read_directives(module, opts) do
    directives =
      if function_exported?(module, :directives, 1) do
        safe_apply(module, :directives, [opts], "Agent Plugin directives/1 failed")
      else
        []
      end

    cond do
      not is_list(directives) ->
        invalid("Agent Plugin directives/1 must return a list", %{
          plugin: module,
          directives: directives
        })

      Enum.any?(directives, &(not is_atom(&1))) ->
        invalid("Agent Plugin Directive modules must be atoms", %{
          plugin: module,
          directives: directives
        })

      Enum.uniq(directives) != directives ->
        invalid("Agent Plugin Directive modules must be unique", %{
          plugin: module,
          directives: directives
        })

      Enum.any?(directives, &Jido.Agent.Directive.built_in_module?/1) ->
        invalid("Agent Plugin cannot own a built-in Directive", %{
          plugin: module,
          directives: Enum.filter(directives, &Jido.Agent.Directive.built_in_module?/1)
        })

      true ->
        {:ok, directives}
    end
  end

  defp validate_directive_contract(module, directives) do
    validates? = function_exported?(module, :validate_directive, 2)
    reduces? = function_exported?(module, :update_state, 3)
    dispatches? = function_exported?(module, :dispatch, 4)

    cond do
      directives != [] and not validates? ->
        invalid("Agent Plugin with Directives must define validate_directive/2", %{
          plugin: module
        })

      directives != [] and not reduces? and not dispatches? ->
        invalid("Agent Plugin Directives must update state or dispatch runtime work", %{
          plugin: module
        })

      dispatches? and directives == [] ->
        invalid("Agent Plugin dispatch/4 requires declared Directives", %{plugin: module})

      true ->
        :ok
    end
  end

  defp validate_state_update_contract(module, nil) do
    if function_exported?(module, :update_state, 3) do
      invalid("Agent Plugin update_state/3 requires state_spec/1", %{plugin: module})
    else
      :ok
    end
  end

  defp validate_state_update_contract(_module, _state_key), do: :ok

  defp unique_modules(specs) do
    unique_by(specs, & &1.module, "Agent Plugin modules must be unique", :plugin)
  end

  defp unique_state_keys(specs) do
    specs
    |> Enum.reject(&is_nil(&1.state_key))
    |> unique_by(& &1.state_key, "Agent Plugin state keys must be unique", :state_key)
  end

  defp unique_directives(specs) do
    specs
    |> Enum.flat_map(fn spec -> Enum.map(spec.directive_modules, &{&1, spec.module}) end)
    |> unique_by(&elem(&1, 0), "Agent Plugin Directive ownership must be unique", :directive)
  end

  defp unique_by(values, key_fun, message, detail_key) do
    case values
         |> Enum.group_by(key_fun)
         |> Enum.find(fn {_key, group} -> length(group) > 1 end) do
      nil -> :ok
      {key, group} -> invalid(message, %{detail_key => key, declarations: group})
    end
  end

  defp state_key_conflicts(fields, specs) do
    domain_keys = MapSet.new(Keyword.keys(fields))

    case Enum.find(specs, &(&1.state_key && MapSet.member?(domain_keys, &1.state_key))) do
      nil ->
        :ok

      spec ->
        invalid("Agent Plugin state key conflicts with the Agent domain schema", %{
          plugin: spec.module,
          state_key: spec.state_key
        })
    end
  end

  defp prepare_all(command, specs) do
    Enum.reduce_while(specs, {:ok, command}, fn spec, {:ok, command} ->
      case prepare_one(command, spec) do
        {:ok, command} -> {:cont, {:ok, command}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp prepare_one(command, %Spec{module: module, options: opts}) do
    if function_exported?(module, :prepare, 2) do
      safe_apply(module, :prepare, [command, opts], "Agent Plugin prepare/2 failed")
      |> case do
        {:ok, %Command{} = prepared} ->
          with {:ok, prepared} <- Command.validate(prepared),
               true <- prepared.agent == command.agent do
            {:ok, prepared}
          else
            false ->
              plugin_invalid("Agent Plugin cannot replace the Agent", module, %{})

            {:error, _reason} = error ->
              error
          end

        {:error, _reason} = error ->
          error

        result ->
          plugin_invalid("Agent Plugin prepare/2 returned an invalid result", module, %{
            result: result
          })
      end
    else
      {:ok, command}
    end
  end

  defp admit_one(command, %Spec{module: module, options: opts}, runtime_ref) do
    if function_exported?(module, :admit, 3) do
      safe_apply(module, :admit, [runtime_ref, command, opts], "Agent Plugin admission failed")
      |> validate_admission_result(command, module)
    else
      {:ok, command}
    end
  end

  defp prepare_dispatch_one(
         signal,
         %Spec{module: module, options: opts},
         runtime_ref,
         context
       ) do
    if function_exported?(module, :prepare_dispatch, 4) do
      safe_apply(
        module,
        :prepare_dispatch,
        [runtime_ref, signal, context, opts],
        "Agent Plugin outbound Signal preparation failed"
      )
      |> case do
        {:ok, %Jido.Signal{} = prepared} ->
          {:ok, prepared}

        {:error, _reason} = error ->
          error

        result ->
          plugin_invalid(
            "Agent Plugin prepare_dispatch/4 returned an invalid result",
            module,
            %{result: result}
          )
      end
    else
      {:ok, signal}
    end
  end

  defp validate_admission_result(result, original, module) do
    case result do
      {:ok, %Command{} = command} ->
        with {:ok, command} <- Command.validate(command),
             true <- command.agent == original.agent do
          {:ok, command}
        else
          false ->
            plugin_invalid("Agent Plugin cannot replace the Agent", module, %{callback: :admit})

          {:error, _reason} = error ->
            error
        end

      {:error, _reason} = error ->
        error

      invalid_result ->
        plugin_invalid(
          "Agent Plugin admit/3 returned an invalid result",
          module,
          %{result: invalid_result}
        )
    end
  end

  defp callback_modules(specs, function, arity) do
    specs
    |> Enum.filter(&function_exported?(&1.module, function, arity))
    |> Enum.map(& &1.module)
  end

  defp plugin_state(_state, nil), do: nil
  defp plugin_state(state, key), do: Map.get(state, key)

  defp apply_state_updates({:ok, state, directives}, specs) do
    Enum.reduce_while(specs, {:ok, state, directives}, fn spec, {:ok, state, directives} ->
      if function_exported?(spec.module, :update_state, 3) do
        current = Map.get(state, spec.state_key)
        owned_directives = owned_directives(directives, spec)

        result =
          safe_apply(
            spec.module,
            :update_state,
            [current, owned_directives, spec.options],
            "Agent Plugin update_state/3 failed"
          )

        case result do
          {:ok, next} ->
            case Zoi.parse(spec.state_schema, next) do
              {:ok, validated} ->
                {:cont, {:ok, Map.put(state, spec.state_key, validated), directives}}

              {:error, errors} ->
                {:halt,
                 plugin_invalid("Agent Plugin state is invalid", spec.module, %{errors: errors})}
            end

          {:error, _reason} = error ->
            {:halt, error}

          invalid_result ->
            {:halt,
             plugin_invalid(
               "Agent Plugin update_state/3 returned an invalid result",
               spec.module,
               %{result: invalid_result}
             )}
        end
      else
        {:cont, {:ok, state, directives}}
      end
    end)
  end

  defp apply_state_updates(result, _specs), do: result

  defp owned_directives(directives, %Spec{directive_modules: modules}) do
    Enum.filter(directives, fn
      %{__struct__: module} -> module in modules
      _directive -> false
    end)
  end

  defp changed_keys(before, after_state, keys) when is_map(before) and is_map(after_state) do
    Enum.filter(keys, &(Map.fetch(before, &1) != Map.fetch(after_state, &1)))
  end

  defp child_specs_for(specs, init_fun) do
    specs
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, child_specs} ->
      case child_spec(spec, init_fun.(spec)) do
        :none -> {:cont, {:ok, child_specs}}
        {:ok, child_spec} -> {:cont, {:ok, [child_spec | child_specs]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, child_specs} -> {:ok, Enum.reverse(child_specs)}
      error -> error
    end
  end

  defp child_spec(%Spec{runtime?: false}, _init), do: :none

  defp child_spec(%Spec{} = spec, %Init{} = init) do
    try do
      {spec.module, init}
      |> Supervisor.child_spec(id: spec.module)
      |> validate_child_spec(spec.module)
    rescue
      error ->
        invalid("Agent Plugin child_spec/1 raised", %{plugin: spec.module, error: error})
    catch
      kind, reason ->
        invalid("Agent Plugin child_spec/1 failed", %{
          plugin: spec.module,
          kind: kind,
          reason: reason
        })
    end
  end

  defp validate_child_spec(%{start: {module, function, args}} = spec, plugin)
       when is_atom(module) and is_atom(function) and is_list(args) do
    case Map.get(spec, :restart, :permanent) do
      :permanent ->
        {:ok, spec}

      restart ->
        invalid("Agent Plugin runtime root must use :permanent restart", %{
          plugin: plugin,
          restart: restart
        })
    end
  end

  defp validate_child_spec(spec, plugin),
    do:
      invalid("Agent Plugin child_spec/1 returned an invalid child specification", %{
        plugin: plugin,
        child_spec: spec
      })

  defp safe_apply(module, function, args, message) do
    apply(module, function, args)
  rescue
    error -> {:error, plugin_error(message, module, %{error: error})}
  catch
    kind, reason ->
      {:error, plugin_error(message, module, %{kind: kind, reason: reason})}
  end

  defp plugin_invalid(message, module, details),
    do: {:error, plugin_error(message, module, details)}

  defp plugin_error(message, module, details),
    do: Error.execution_error(message, details: Map.put(details, :plugin, module))

  defp invalid(message, details),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}
end
