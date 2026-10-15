defmodule JidoTest.Property.Authoring do
  @moduledoc false

  defdelegate with_compiled(source, callback, options \\ []), to: JidoTest.AuthoringCompiler
end
