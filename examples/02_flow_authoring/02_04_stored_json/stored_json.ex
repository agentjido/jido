defmodule Jido.Examples.Compilation.StoredJSON.Echo do
  use Jido.Action,
    id: "jido/examples/compilation/json_echo",
    vsn: 1,
    name: "example_compile_json_echo"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Compilation.StoredJSON do
  alias Jido.Examples.Compilation.StoredJSON.Echo
  alias Jido.Flow.Ref

  def flow do
    Jido.Flow.new!(%{
      name: "example_compile_json",
      components: [%{kind: :step, name: "echo", action: Echo}],
      output: Ref.result("echo")
    })
  end

  def catalog do
    Jido.Catalog.from_targets!(__MODULE__, :jido, %{
      {"jido/examples/compilation/json_echo", 1} => Echo,
      {"jido/examples/compilation/empty_schema", 1} => Jido.Joi.map()
    })
  end

  def document do
    {:ok, json} = Jido.Codec.encode_json(flow(), catalog: catalog())

    json
  end

  def decode(json \\ document()) do
    {:ok, codec} = Jido.Codec.Encoder.codec(flow())
    Jido.Codec.decode_json(json, catalog: catalog(), codec: codec)
  end
end
