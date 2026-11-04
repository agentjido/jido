defmodule Jido.Examples.Compilation.AuthoringEquivalence.Echo do
  use Jido.Action,
    id: "jido/examples/compilation/equivalent_echo",
    vsn: 1,
    name: "example_authoring_equivalence_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.AuthoringEquivalence do
  use Jido.Flow, name: "example_authoring_equivalence"

  alias Jido.Examples.Compilation.AuthoringEquivalence.Echo
  alias Jido.Flow.Ref

  flow do
    step "echo", action: Echo, params: %{message: input(:message)}
    output result("echo")
  end

  def from_map do
    Jido.Flow.new!(%{
      name: "example_authoring_equivalence",
      components: [
        %{kind: :step, name: "echo", action: Echo, params: %{message: Ref.input(:message)}}
      ],
      output: Ref.result("echo")
    })
  end

  def catalog do
    Jido.Catalog.from_targets!(__MODULE__, :jido, %{
      {"jido/examples/compilation/equivalent_echo", 1} => {:action, Echo},
      {"jido/examples/compilation/message", 1} => {:atom, :message},
      {"jido/examples/compilation/empty_schema", 1} => {:schema, Jido.Joi.map()}
    })
  end

  def from_json do
    options = [catalog: catalog(), codec: Jido.Flow.Codec]

    with {:ok, json} <- Jido.Codec.encode_json(from_map(), options) do
      Jido.Codec.decode_json(json, options)
    end
  end
end
