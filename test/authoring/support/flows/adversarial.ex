defmodule JidoActionTest.Authoring.Adversarial.Echo do
  use Jido.Action, name: "authoring_adversarial_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Authoring.Adversarial.Sum do
  use Jido.Action, name: "authoring_adversarial_sum"

  @impl true
  def run(%{a: a, b: b, c: c}, _context), do: {:ok, %{sum: a + b + c}}
end
