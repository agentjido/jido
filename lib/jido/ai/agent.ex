defmodule Jido.AI.Agent do
  @moduledoc """
  Defines a graph-first AI Agent with a Spark-backed Agent Plugin.

  An AI Agent selects one root reasoning Flow and an optional ordered set of
  tool Actions and Flows:

      defmodule MyApp.SupportAgent do
        use Jido.AI.Agent, name: "support_agent"

        ai do
          reasoning MyApp.SupportReasoning

          tools do
            action MyApp.SearchDocs
            action MyApp.CreateTicket
          end
        end
      end

  The reasoning Flow is the direct target of the `jido.ai.request` route.
  Jido AI does not add a hidden pipeline around it.

  A reasoning block sets partial input defaults. The selected Flow input
  schema defines all fields, types, defaults, and validation:

      ai do
        reasoning Jido.AI.Reasoning.ReAct do
          instructions "Answer as a support specialist."
          model "anthropic:claude-sonnet-4-5"

          limits do
            model_calls 8
            tool_rounds 4
          end
        end
      end

  Small Agents can define the root Flow inline:

      ai do
        reasoning do
          step "answer", question <- input(:question), inline: [context: context] do
            {:ok, %{state: context.agent_state, response: %{answer: question}}}
          end

          output result("answer")
        end
      end

  The `ai`, `reasoning`, and `tools` declarations lower through an internal
  Plugin. The Plugin contributes the normal Agent route and stores its
  authoring data in the normal Agent codec document.
  Registered Flow and Action references are required when the Agent is stored
  as JSON.
  """

  alias Jido.AI.Agent.Plugin

  @doc "Uses the Jido Agent runtime with the graph-first AI Plugin."
  defmacro __using__(quoted_options) do
    options =
      quoted_options
      |> Jido.Agent.Options.prepare!(__CALLER__)
      |> Jido.Agent.Options.prepend_plugin(Plugin)

    signal_source = "/" <> Keyword.fetch!(options, :id)

    quote do
      use Jido.Agent, unquote(Macro.escape(options))

      state do
        schema Zoi.object(%{session: Jido.AI.Thread.Projection.schema()})
      end

      routes do
        signal_source unquote(signal_source)
      end

      @doc "Returns this Agent's root reasoning Flow module."
      @spec reasoning() :: module()
      def reasoning, do: Jido.AI.Reasoning.root(__MODULE__)

      @doc "Returns this Agent's root Flow, schemas, defaults, and tools."
      @spec explain() :: map()
      def explain, do: Jido.AI.Reasoning.explain(__MODULE__)

      @doc "Validates one request and compiles the root Flow without running it."
      @spec preflight(map() | keyword()) :: {:ok, map()} | {:error, term()}
      def preflight(input), do: Jido.AI.Reasoning.preflight(__MODULE__, input)
    end
  end
end
