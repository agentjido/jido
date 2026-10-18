defmodule JidoTest.ComposableAgent.Compiler do
  def compile(body, opts \\ "name: \"generated\"") do
    name = "JidoTest.ComposableAgent.Generated.M#{System.unique_integer([:positive])}"
    source = "defmodule #{name} do\nuse Jido.Agent, #{opts}\n#{body}\nend\n"
    path = Path.join(System.tmp_dir!(), "agent_#{System.unique_integer([:positive])}.ex")
    File.write!(path, source)

    try do
      Code.compile_file(path)
      String.to_existing_atom("Elixir." <> name)
    after
      File.rm!(path)
    end
  end
end
