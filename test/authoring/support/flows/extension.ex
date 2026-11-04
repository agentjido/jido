defmodule JidoActionTest.Authoring.Extension.WatchStep do
  use Jido.Flow.Extension

  defmacro watch_step(name, value) do
    quote do
      step unquote(name),
        action: JidoActionTest.Authoring.Hostile.Watch,
        params: %{id: unquote(name), value: unquote(value)}
    end
  end
end

defmodule JidoActionTest.Authoring.Extension.Extended do
  use Jido.Flow,
    name: "authoring_extended",
    extensions: [JidoActionTest.Authoring.Extension.WatchStep]

  flow do
    watch_step("observed", input(:value))
    output result("observed")
  end
end

defmodule JidoActionTest.Authoring.Extension.Plain do
  use Jido.Flow, name: "authoring_extended"

  flow do
    step "observed",
      action: JidoActionTest.Authoring.Hostile.Watch,
      params: %{id: "observed", value: input(:value)}

    output result("observed")
  end
end
