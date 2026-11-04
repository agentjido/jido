defmodule Jido.Test.Flow.Authoring.MissingOutput do
  use Jido.Flow, name: "authoring_missing_output"

  flow do
    step "greet",
      action: Jido.Test.Flow.Authoring.Greeting.Greet,
      params: %{name: input(:name)}
  end
end
