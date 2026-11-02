defmodule Jido.Flow.DSL.Forms.Map do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :map,
    args: [:name],
    identifier: :name,
    modules: [:action],
    describe: "Maps one Action or Flow Instruction over an ordered collection.",
    schema:
      [
        name: [type: :any, required: true, doc: "The unique Map name."],
        collection: [type: :quoted, required: true, doc: "The collection expression."],
        action: [type: :atom, required: true, doc: "The Action or Flow module to call."],
        params: [type: :quoted, required: true, doc: "Parameters for each item call."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."],
        on_error: [
          type: {:one_of, [:fail_fast, :collect_errors]},
          default: :fail_fast,
          doc: "The item failure policy."
        ]
      ] ++ Jido.Flow.DSL.Entity.policy_schema()
end

defmodule Jido.Flow.DSL.Forms.Reduce do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :reduce,
    args: [:name],
    identifier: :name,
    modules: [:action],
    describe: "Reduces an ordered collection with one Action call per item.",
    schema:
      [
        name: [type: :any, required: true, doc: "The unique Reduce name."],
        collection: [type: :quoted, required: true, doc: "The collection expression."],
        initial: [type: :quoted, required: true, doc: "The initial accumulator expression."],
        action: [type: :atom, required: true, doc: "The Action module to call."],
        params: [type: :quoted, required: true, doc: "Parameters for each item call."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."]
      ] ++ Jido.Flow.DSL.Entity.policy_schema()
end

defmodule Jido.Flow.DSL.Forms.Choice.Option do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :option,
    args: [:name],
    identifier: :name,
    modules: [:action],
    describe: "Declares one ordered Choice option.",
    schema:
      [
        name: [type: :any, required: true, doc: "The unique option name."],
        condition: [type: :quoted, required: true, doc: "The Boolean condition expression."],
        action: [type: :atom, required: true, doc: "The Action or Flow module to call."],
        params: [type: :quoted, required: true, doc: "Parameters for the selected call."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."]
      ] ++ Jido.Flow.DSL.Entity.policy_schema()
end

defmodule Jido.Flow.DSL.Forms.Choice.Otherwise do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :otherwise,
    modules: [:action],
    describe: "Declares the required Choice fallback.",
    schema:
      [
        action: [type: :atom, required: true, doc: "The Action or Flow module to call."],
        params: [type: :quoted, required: true, doc: "Parameters for the fallback call."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."]
      ] ++ Jido.Flow.DSL.Entity.policy_schema()
end

defmodule Jido.Flow.DSL.Forms.Choice do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :choice,
    args: [:name],
    identifier: :name,
    describe: "Selects the first true option or the required fallback.",
    schema: [name: [type: :any, required: true, doc: "The unique Choice name."]],
    entities: [
      options: [Jido.Flow.DSL.Forms.Choice.Option.entity()],
      fallback: [Jido.Flow.DSL.Forms.Choice.Otherwise.entity()]
    ],
    singleton_entity_keys: [:fallback]
end

defmodule Jido.Flow.DSL.Forms.Parallel.Action do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :action,
    args: [:name, :action],
    identifier: :name,
    modules: [:action],
    describe: "Declares one named Action in a Parallel form.",
    schema:
      [
        name: [type: :any, required: true, doc: "The unique Action name."],
        action: [type: :atom, required: true, doc: "The Action module to call."],
        params: [type: :quoted, required: true, doc: "Parameters for the Action call."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."]
      ] ++ Jido.Flow.DSL.Entity.policy_schema()
end

defmodule Jido.Flow.DSL.Forms.Parallel do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__parallel__,
    args: [:name],
    identifier: :name,
    describe: "Runs a fixed ordered group of independent Actions.",
    schema: [
      name: [type: :any, required: true, doc: "The unique Parallel name."],
      on_error: [
        type: {:one_of, [:fail_fast, :collect_errors]},
        default: :fail_fast,
        doc: "The shared Action failure policy."
      ]
    ],
    entities: [actions: [Jido.Flow.DSL.Forms.Parallel.Action.entity()]]
end

defmodule Jido.Flow.DSL.Forms.BlockMacros do
  @moduledoc false

  alias Jido.Flow.DSL.MacroSupport

  defmacro parallel(name, do: block), do: block_entity(:parallel, name, [], block, __CALLER__)

  defmacro parallel(_name, _options) do
    MacroSupport.compile_error!(__CALLER__, "Parallel declaration requires one do block")
  end

  defmacro parallel(name, options, do: block),
    do: block_entity(:parallel, name, options, block, __CALLER__)

  defmacro selection(name, do: block), do: block_entity(:selection, name, [], block, __CALLER__)

  defmacro selection(_name, _options) do
    MacroSupport.compile_error!(__CALLER__, "Selection declaration requires one do block")
  end

  defmacro selection(name, options, do: block),
    do: block_entity(:selection, name, options, block, __CALLER__)

  defp block_entity(kind, name, options, block, caller) do
    MacroSupport.validate_options!(
      options,
      caller,
      "#{kind |> Atom.to_string() |> String.capitalize()} declaration options must be a keyword list",
      "#{kind |> Atom.to_string() |> String.capitalize()} field"
    )

    module = block_module(kind)
    fields = Keyword.put(options, :do, block)

    quote generated: true, line: caller.line, file: caller.file do
      require unquote(module)
      unquote(module).unquote(block_function(kind))(unquote(name), unquote(fields))
    end
  end

  defp block_module(:parallel), do: Jido.Flow.DSL.Forms.Flow.Parallel
  defp block_module(:selection), do: Jido.Flow.DSL.Forms.Flow.Selection
  defp block_function(:parallel), do: :__parallel__
  defp block_function(:selection), do: :__selection__
end

defmodule Jido.Flow.DSL.Forms.Iterate.State do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :state,
    args: [:schema],
    modules: [:schema],
    describe: "Declares the Iterate state schema and initial value.",
    schema: [
      schema: [type: :any, required: true, doc: "The static state schema."],
      initial: [type: :quoted, required: true, doc: "The initial state expression."]
    ]
end

defmodule Jido.Flow.DSL.Forms.Iterate do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :iterate,
    args: [:name],
    identifier: :name,
    modules: [:action],
    describe: "Runs one Action or Flow Instruction in a bounded state loop.",
    schema:
      [
        name: [type: :any, required: true, doc: "The unique Iterate name."],
        action: [type: :atom, required: true, doc: "The loop body Action or Flow module."],
        params: [type: :quoted, required: true, doc: "Parameters for each body call."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."],
        update: [type: :quoted, doc: "The replacement state after each body call."],
        while: [type: :quoted, doc: "The Boolean condition checked before each body call."],
        repeat: [type: :pos_integer, doc: "A fixed iteration count."],
        max_iterations: [type: :pos_integer, doc: "The maximum count for a While loop."]
      ] ++ Jido.Flow.DSL.Entity.policy_schema(),
    entities: [state: [Jido.Flow.DSL.Forms.Iterate.State.entity()]],
    singleton_entity_keys: [:state]
end

defmodule Jido.Flow.DSL.Forms.Invoke.Macros do
  @moduledoc false

  alias Jido.Flow.DSL.MacroSupport

  defmacro invoke(name, options) do
    caller = __CALLER__

    MacroSupport.validate_options!(
      options,
      caller,
      "Invoke declaration options must be a keyword list",
      "Invoke field"
    )

    options = expand_targets!(options, caller)
    module = Jido.Flow.DSL.Forms.Flow.Invoke

    quote generated: true, line: caller.line, file: caller.file do
      require unquote(module)
      unquote(module).__invoke__(unquote(name), unquote(options))
    end
  end

  @doc false
  @spec expand_targets!(keyword(), Macro.Env.t()) :: keyword()
  def expand_targets!(options, caller) do
    case Keyword.fetch(options, :targets) do
      {:ok, targets_ast} ->
        Keyword.put(options, :targets, Macro.escape(expand_target_map!(targets_ast, caller)))

      :error ->
        options
    end
  end

  defp expand_target_map!(targets_ast, caller) do
    case Macro.expand(targets_ast, caller) do
      {:%{}, _metadata, pairs} when is_list(pairs) ->
        Map.new(pairs, fn {id, target} -> {id, Macro.expand(target, caller)} end)

      _other ->
        MacroSupport.compile_error!(caller, "Invoke targets must be a map")
    end
  end
end

defmodule Jido.Flow.DSL.Forms.Invoke do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__invoke__,
    args: [:name],
    identifier: :name,
    describe: "Selects one declared Action or Flow by a runtime string ID.",
    schema:
      [
        name: [type: :any, required: true, doc: "The unique Invoke name."],
        target: [type: :quoted, required: true, doc: "The target ID expression."],
        targets: [type: :any, required: true, doc: "The closed target table."],
        params: [type: :quoted, default: %{}, doc: "The selected target parameters."],
        meta: [type: {:map, :any, :any}, default: %{}, doc: "Instruction metadata."],
        on_error: [
          type: {:one_of, [:fail_fast, :collect_errors]},
          default: :fail_fast,
          doc: "Fails the Flow or returns a tagged Invoke outcome."
        ]
      ] ++ Jido.Flow.DSL.Entity.policy_schema()
end

defmodule Jido.Flow.DSL.Forms.Wait.Await do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :await,
    args: [:name],
    identifier: :name,
    describe: "Waits for one matching host event.",
    schema: [
      name: [type: :any, required: true, doc: "The unique Await name."],
      event: [type: :string, required: true, doc: "The host event name."],
      match: [type: :quoted, default: {:%{}, [], []}, doc: "Fields that the event must match."]
    ]
end

defmodule Jido.Flow.DSL.Forms.Wait.Timer do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :timer,
    args: [:name],
    identifier: :name,
    describe: "Waits until a delay from activation has passed.",
    schema: [
      name: [type: :any, required: true, doc: "The unique Timer name."],
      after_ms: [type: :non_neg_integer, required: true, doc: "The delay in milliseconds."]
    ]
end

defmodule Jido.Flow.DSL.Forms.Wait.Selection.Await do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :await,
    args: [:name],
    identifier: :name,
    describe: "Declares one event option in a Selection.",
    schema: [
      name: [type: :any, required: true, doc: "The unique option name."],
      event: [type: :string, required: true, doc: "The host event name."],
      match: [type: :quoted, default: {:%{}, [], []}, doc: "Fields that the event must match."]
    ]
end

defmodule Jido.Flow.DSL.Forms.Wait.Selection.Timer do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    name: :timer,
    args: [:name],
    identifier: :name,
    describe: "Declares one timer option in a Selection.",
    schema: [
      name: [type: :any, required: true, doc: "The unique option name."],
      after_ms: [type: :non_neg_integer, required: true, doc: "The delay in milliseconds."]
    ]
end

defmodule Jido.Flow.DSL.Forms.Wait.Selection do
  @moduledoc false

  use Jido.Flow.DSL.Entity,
    node?: true,
    name: :__selection__,
    args: [:name],
    identifier: :name,
    describe: "Waits for the first matching event or timer.",
    schema: [name: [type: :any, required: true, doc: "The unique Selection name."]],
    entities: [
      clauses: [
        Jido.Flow.DSL.Forms.Wait.Selection.Await.entity(),
        Jido.Flow.DSL.Forms.Wait.Selection.Timer.entity()
      ]
    ]
end

defmodule Jido.Flow.DSL.Forms do
  @moduledoc false

  @entities [
    Jido.Flow.DSL.Forms.Map,
    Jido.Flow.DSL.Forms.Reduce,
    Jido.Flow.DSL.Forms.Choice,
    Jido.Flow.DSL.Forms.Parallel,
    Jido.Flow.DSL.Forms.Iterate,
    Jido.Flow.DSL.Forms.Invoke,
    Jido.Flow.DSL.Forms.Wait.Await,
    Jido.Flow.DSL.Forms.Wait.Timer,
    Jido.Flow.DSL.Forms.Wait.Selection
  ]

  use Spark.Dsl.Extension,
    imports: [Jido.Flow.DSL.Forms.BlockMacros, Jido.Flow.DSL.Forms.Invoke.Macros],
    dsl_patches:
      Enum.map(@entities, fn entity ->
        %Spark.Dsl.Patch.AddEntity{section_path: [:flow], entity: entity.entity()}
      end)
end
