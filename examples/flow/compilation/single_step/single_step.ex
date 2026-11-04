defmodule Jido.Examples.Compilation.SingleStep.Echo do
  use Jido.Action, name: "example_compile_single_step_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.SingleStep do
  alias Jido.Examples.Compilation.SingleStep.Echo
  alias Jido.Flow.Ref

  def definition do
    %{
      name: "example_compile_single_step",
      components: [
        %{kind: :step, name: "echo", action: Echo, params: %{message: Ref.input(:message)}}
      ],
      output: Ref.result("echo")
    }
  end

  def flow, do: Jido.Flow.new!(definition())
end
