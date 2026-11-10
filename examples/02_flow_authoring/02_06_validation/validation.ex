defmodule Jido.Examples.Compilation.Validation.Echo do
  use Jido.Action, name: "example_compile_validation_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.Validation do
  alias Jido.Examples.Compilation.Validation.Echo
  alias Jido.Flow.Ref

  def missing_result do
    %{
      name: "example_missing_result",
      components: [
        %{kind: :step, name: "save", action: Echo, params: %{value: Ref.result("missing")}}
      ],
      output: Ref.result("save")
    }
  end

  def cycle do
    %{
      name: "example_cycle",
      components: [
        %{kind: :step, name: "first", action: Echo, needs: ["second"]},
        %{kind: :step, name: "second", action: Echo, needs: ["first"]}
      ],
      output: Ref.result("second")
    }
  end
end
