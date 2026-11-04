defmodule Jido.Examples.Durability.RunIdentity.Echo do
  use Jido.Action, name: "example_run_identity_echo"

  @impl true
  def run(params, _context), do: {:ok, params, [:identified]}
end

defmodule Jido.Examples.Durability.RunIdentity do
  use Jido.Flow, name: "example_run_identity"

  alias Jido.Examples.Durability.RunIdentity.Echo

  flow do
    step "echo", action: Echo, params: %{value: input(:value)}
    output result("echo")
  end
end
