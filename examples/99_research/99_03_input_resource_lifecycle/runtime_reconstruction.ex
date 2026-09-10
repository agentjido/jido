defmodule Jido.Examples.RuntimeReconstruction do
  @moduledoc "Keeps desired feed state while a replaceable input runtime owns the live resource."
  use Jido.Agent, name: "research_runtime_reconstruction"

  agent do
    schema Zoi.object(%{items: Zoi.list(Zoi.string()) |> Zoi.default([])})
    plugin __MODULE__.Plugin
  end

  routes do
    signal_source "/examples/research/runtime_reconstruction"

    route "examples.research.runtime_reconstruction.feed.select" do
      action %{name: name},
        schema: Zoi.object(%{name: Zoi.string() |> Zoi.min(1)}),
        context: context do
        {:ok, context.agent_state, [%__MODULE__.SetFeed{feed: name}]}
      end

      define :select, args: [:name]
    end

    route "examples.research.runtime_reconstruction.feed.input" do
      action %{feed: feed, text: text},
        schema: Zoi.object(%{feed: Zoi.string(), text: Zoi.string()}),
        context: context do
        if context.agent_state.feed.name == feed do
          {:ok, %{context.agent_state | items: context.agent_state.items ++ [text]}}
        else
          {:error, Jido.Action.Error.validation_error("stale feed")}
        end
      end
    end
  end
end
