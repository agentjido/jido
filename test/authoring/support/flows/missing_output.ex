defmodule JidoActionTest.Authoring.MissingOutput do
  use Jido.Flow, name: "authoring_missing_output"

  flow do
    step "greet",
      action: JidoActionTest.Authoring.Greeting.Greet,
      params: %{name: input(:name)}
  end
end
