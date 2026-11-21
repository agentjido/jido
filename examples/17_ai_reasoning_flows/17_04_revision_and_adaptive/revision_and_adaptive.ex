defmodule Jido.Examples.AI.Reasoning.RevisionAndAdaptive do
  @moduledoc "Compares a fixed revision cycle with locally selected reasoning."

  alias Jido.AI.Reasoning.{Adaptive, TRM}

  use Jido.Flow,
    name: "examples_ai_revision_and_adaptive",
    schema:
      Jido.Joi.object(
        %{input: Jido.Joi.string()},
        unrecognized_keys: :error
      )

  flow do
    step "revision",
      action: TRM,
      params: %{
        input: input(:input),
        model: "offline:trm",
        options: %{offline_strategy: :trm}
      }

    step "adaptive",
      action: Adaptive,
      params: %{
        input: input(:input),
        model: "offline:adaptive",
        options: %{offline_strategy: :adaptive}
      }

    output %{revision: result("revision"), adaptive: result("adaptive")}
  end
end
