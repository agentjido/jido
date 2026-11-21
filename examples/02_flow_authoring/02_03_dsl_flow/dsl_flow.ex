defmodule Jido.Examples.Compilation.DSLFlow.Echo do
  use Jido.Action, name: "example_compile_dsl_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.DSLFlow do
  use Jido.Flow, name: "example_compile_dsl"

  alias Jido.Examples.Compilation.DSLFlow.Echo

  flow do
    step "echo", action: Echo, params: %{message: input(:message)}
    output result("echo")
  end
end
