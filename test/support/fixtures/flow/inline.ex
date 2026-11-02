defmodule JidoActionTest.Fixtures.InlineGreetingFlow do
  @moduledoc false
  use Jido.Flow, name: "inline_greeting"

  flow do
    step("normalize", name <- input(:name)) do
      {:ok, %{name: String.trim(name)}}
    end

    step("greet", name <- result("normalize", :name)) do
      {:ok, %{message: "Hello, " <> name <> "!"}}
    end

    output(result("greet"))
  end
end

defmodule JidoActionTest.Fixtures.InlineParityFlow do
  @moduledoc false
  use Jido.Flow, name: "inline_parity", description: "All inline binding forms"

  flow do
    step("empty", []) do
      {:ok, %{ready: true}}
    end

    step("named", name <- input(:raw_name), needs: ["empty"], meta: %{owner: "inline"}) do
      {:ok, %{name: String.trim(name)}}
    end

    step("multiple", [name <- result("named", :name), prefix <- context(:prefix)],
      needs: ["empty"],
      meta: %{purpose: "greeting"}
    ) do
      {:ok, %{message: prefix <> ", " <> name <> "!"}}
    end

    step(
      "sole_map",
      %{"profile" => %{"city" => city}, "active" => true} <- input(:payload),
      needs: ["multiple"]
    ) do
      {:ok, %{city: city}}
    end

    output(%{
      "empty" => result("empty"),
      "greeting" => result("multiple"),
      "profile" => result("sole_map")
    })
  end
end

defmodule JidoActionTest.Fixtures.InlineAuthoring do
  @moduledoc false
  alias Jido.Authoring.Registry
  alias JidoActionTest.Fixtures.InlineParityFlow

  def direct_flow! do
    JidoActionTest.FlowBuilder.new!(data())
  end

  def data do
    %{
      output: %{
        "empty" => Jido.Flow.Ref.result("empty"),
        "greeting" => Jido.Flow.Ref.result("multiple"),
        "profile" => Jido.Flow.Ref.result("sole_map")
      },
      components: [
        %{kind: :step, name: "empty", action: InlineParityFlow.step_action("empty"), params: %{}},
        %{
          kind: :step,
          name: "named",
          action: InlineParityFlow.step_action("named"),
          params: %{name: Jido.Flow.Ref.input(:raw_name)},
          needs: ["empty"],
          meta: %{owner: "inline"}
        },
        %{
          kind: :step,
          name: "multiple",
          action: InlineParityFlow.step_action("multiple"),
          params: %{
            name: Jido.Flow.Ref.result("named", :name),
            prefix: Jido.Flow.Ref.context(:prefix)
          },
          needs: ["empty"],
          meta: %{purpose: "greeting"}
        },
        %{
          kind: :step,
          name: "sole_map",
          action: InlineParityFlow.step_action("sole_map"),
          params: Jido.Flow.Ref.input(:payload),
          needs: ["multiple"]
        }
      ],
      name: "inline_parity",
      description: "All inline binding forms"
    }
  end

  def registry do
    Registry.new!(%{
      {"actions/demo/empty/v1", 1} => {:action, InlineParityFlow.step_action("empty")},
      {"actions/demo/named/v1", 1} => {:action, InlineParityFlow.step_action("named")},
      {"actions/demo/multiple/v1", 1} => {:action, InlineParityFlow.step_action("multiple")},
      {"actions/demo/sole-map/v1", 1} => {:action, InlineParityFlow.step_action("sole_map")},
      {"schemas/map/v1", 1} => {:schema, Zoi.map()},
      {"schemas/object/v1", 1} => {:schema, Zoi.object(%{})},
      {"atoms/name", 1} => {:atom, :name},
      {"atoms/raw-name", 1} => {:atom, :raw_name},
      {"atoms/prefix", 1} => {:atom, :prefix},
      {"atoms/payload", 1} => {:atom, :payload},
      {"atoms/purpose", 1} => {:atom, :purpose},
      {"atoms/owner", 1} => {:atom, :owner}
    })
  end
end

defmodule JidoActionTest.Fixtures.InlineBodyHelpers do
  @moduledoc false
  defmacro decorate(value) do
    quote do
      "[" <> unquote(value) <> "]"
    end
  end

  def step(name, value) do
    %{name: name, value: value}
  end

  def output(value) do
    value
  end
end

defmodule JidoActionTest.Fixtures.InlineLexicalFlow do
  @moduledoc false
  use Jido.Flow, name: "inline_lexical"
  alias String, as: Text
  import String, only: [upcase: 1]
  import JidoActionTest.Fixtures.InlineBodyHelpers, only: [decorate: 1]
  @prefix "before"
  defp before_step(value) do
    value <> "!"
  end

  flow do
    alias JidoActionTest.Fixtures.InlineBodyHelpers, as: Helpers

    step("lexical", name <- input(:name)) do
      {:ok,
       %{
         value: name |> Text.trim() |> upcase() |> before_step() |> after_step() |> decorate(),
         module: __MODULE__,
         prefix: @prefix,
         qualified: Helpers.output(Helpers.step("body", name))
       }}
    end

    step("local_import", data <- result("lexical")) do
      import JidoActionTest.Fixtures.InlineBodyHelpers, only: [step: 2, output: 1]
      {:ok, Map.put(data, :local_import, output(step("local", data.value)))}
    end

    output(result("local_import"))
  end

  @prefix "after"
  def current_prefix do
    @prefix
  end

  defp after_step(value) do
    value <> "?"
  end
end

defmodule JidoActionTest.Fixtures.InlineResultFlow do
  @moduledoc false
  use Jido.Flow, name: "inline_result"
  alias Jido.Action.Output
  alias JidoActionTest.Fixtures.Actions.Add

  flow do
    step("result", %{mode: mode, value: value} <- input()) do
      case mode do
        :map -> {:ok, %{value: value}}
        :output -> {:ok, Output.raw(value)}
        :extras -> {:ok, %{value: value}, [%{effect: :requested}]}
        :raise -> raise "inline body failed"
        :throw -> throw({:inline_throw, value})
        :exit -> exit({:inline_exit, value})
        :invalid_callback -> :not_a_result_tuple
        :invalid_output -> {:ok, value}
        :continue -> {:continue, %{value: value, amount: 2}, Add}
      end
    end

    output(result("result"))
  end
end

defmodule JidoActionTest.Fixtures.InlineControlledFlow do
  @moduledoc false
  use Jido.Flow, name: "inline_controlled"

  flow do
    step("third", [value <- input(:third), ctx <- context()]) do
      controlled(value, ctx)
    end

    step("second", [value <- input(:second), ctx <- context()]) do
      controlled(value, ctx)
    end

    step("first", [value <- input(:first), ctx <- context()]) do
      controlled(value, ctx)
    end

    output(%{
      values: [result("first", :value), result("second", :value), result("third", :value)]
    })
  end

  defp controlled(value, %{test_pid: test_pid, token: token} = ctx) do
    if probe = ctx[:probe] do
      Agent.update(probe, fn state ->
        running = state.running + 1
        %{state | running: running, max: max(state.max, running)}
      end)
    end

    send(test_pid, {:inline_started, token, value, self()})

    if Map.get(ctx, :block, true) do
      receive do
        {:release, ^token} -> :ok
      end
    end

    if probe = ctx[:probe] do
      Agent.update(probe, &%{&1 | running: &1.running - 1})
    end

    send(test_pid, {:inline_finished, token, value})
    {:ok, %{value: value}}
  end
end
