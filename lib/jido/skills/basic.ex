defmodule Jido.Skills.Basic do
  @moduledoc """
  A core skill that provides basic tools and utilities for agents.

  This skill includes fundamental actions that are commonly needed by agents:
  - Logging capabilities
  - Sleep/wait functionality
  - No-operation (noop) for testing
  - Inspection utilities
  - Date/time functions

  These actions form the foundation for agent functionality and are included
  by default in all agents.
  """

  use Jido.Skill,
    name: "basic_tools",
    description: "Provides basic tools and utilities for agents",
    category: "Core",
    tags: ["basic", "tools", "utilities", "core"],
    vsn: "1.0.0",
    opts_key: :basic,
    opts_schema: [],
    signal_patterns: [
      "jido.basic.**"
    ],
    actions: [
      Jido.Tools.Basic.Log,
      Jido.Tools.Basic.Sleep,
      Jido.Tools.Basic.Noop,
      Jido.Tools.Basic.Inspect,
      Jido.Tools.Basic.Today
    ]

  alias Jido.Instruction

  @impl true
  @spec router(keyword()) :: [Jido.Signal.Router.Route.t()]
  def router(_opts) do
    [
      %Jido.Signal.Router.Route{
        path: "jido.basic.log",
        target: %Instruction{action: Jido.Tools.Basic.Log},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.basic.sleep",
        target: %Instruction{action: Jido.Tools.Basic.Sleep},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.basic.noop",
        target: %Instruction{action: Jido.Tools.Basic.Noop},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.basic.inspect",
        target: %Instruction{action: Jido.Tools.Basic.Inspect},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.basic.today",
        target: %Instruction{action: Jido.Tools.Basic.Today},
        priority: 0
      }
    ]
  end

  @impl true
  @spec handle_signal(Jido.Signal.t(), Jido.Skill.t()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def handle_signal(%Jido.Signal{} = signal, _skill) do
    {:ok, signal}
  end

  @impl true
  @spec transform_result(Jido.Signal.t(), term(), Jido.Skill.t()) ::
          {:ok, term()} | {:error, any()}
  def transform_result(_signal, result, _skill) do
    {:ok, result}
  end
end
