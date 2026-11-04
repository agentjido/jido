defmodule Jido.Examples.Compilation.CompiledProgram.Work do
  use Jido.Action, name: "example_compiled_program_work"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.CompiledProgram do
  use Jido.Flow, name: "example_compiled_program"

  alias Jido.Examples.Compilation.CompiledProgram.Work

  flow do
    map "items",
      collection: input(:items),
      action: Work,
      params: %{value: item()}

    choice "selected" do
      option "has_items",
        condition: input(:use_items),
        action: Work,
        params: %{value: result("items")}

      otherwise action: Work, params: %{value: []}
    end

    output result("selected")
  end
end
