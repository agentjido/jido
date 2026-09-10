defmodule Jido.Examples.ReActAgent.Model do
  @moduledoc "The model client contract for the effectful ReAct Flow."

  @type decision :: {:tool, String.t(), term()} | {:answer, String.t()}

  @callback complete(client :: term(), messages :: [map()]) ::
              {:ok, decision()} | {:error, term()}
end

defmodule Jido.Examples.ReActAgent.Tool do
  @moduledoc "The tool client contract for the effectful ReAct Flow."

  @callback run(client :: term(), input :: term()) :: {:ok, term()} | {:error, term()}
end
