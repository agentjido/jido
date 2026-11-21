defmodule Jido.Test.Flow.Fixtures.InlineGreetingFlow do
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

defmodule Jido.Test.Flow.Fixtures.InlineParityFlow do
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

defmodule Jido.Test.Flow.Fixtures.InlineAuthoring do
  @moduledoc false
  alias Jido.Catalog
  alias Jido.Test.Flow.Fixtures.InlineParityFlow

  def direct_flow! do
    Jido.Test.Flow.Builder.new!(data())
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
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"actions/demo/empty/v1", 1} => InlineParityFlow.step_action("empty"),
      {"actions/demo/named/v1", 1} => InlineParityFlow.step_action("named"),
      {"actions/demo/multiple/v1", 1} => InlineParityFlow.step_action("multiple"),
      {"actions/demo/sole-map/v1", 1} => InlineParityFlow.step_action("sole_map"),
      {"schemas/map/v1", 1} => Jido.Joi.map(),
      {"schemas/object/v1", 1} => Jido.Joi.object(%{}),
      {"atoms/name", 1} => :name,
      {"atoms/raw-name", 1} => :raw_name,
      {"atoms/prefix", 1} => :prefix,
      {"atoms/payload", 1} => :payload,
      {"atoms/purpose", 1} => :purpose,
      {"atoms/owner", 1} => :owner
    })
  end
end

defmodule Jido.Test.Flow.Fixtures.InlineBodyHelpers do
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

defmodule Jido.Test.Flow.Fixtures.InlineLexicalFlow do
  @moduledoc false
  use Jido.Flow, name: "inline_lexical"
  alias String, as: Text
  import String, only: [upcase: 1]
  import Jido.Test.Flow.Fixtures.InlineBodyHelpers, only: [decorate: 1]
  @prefix "before"
  defp before_step(value) do
    value <> "!"
  end

  flow do
    alias Jido.Test.Flow.Fixtures.InlineBodyHelpers, as: Helpers

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
      import Jido.Test.Flow.Fixtures.InlineBodyHelpers, only: [step: 2, output: 1]
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
