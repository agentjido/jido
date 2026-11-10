defmodule Jido.Test.Examples.Loader do
  @moduledoc false

  @root Path.expand("../../../examples", __DIR__)

  def require_source!(relative_path) when is_binary(relative_path) do
    source = Path.expand(relative_path, @root)

    unless source != @root and String.starts_with?(source, @root <> "/") do
      raise ArgumentError, "example source must stay under examples/"
    end

    unless File.regular?(source) do
      raise ArgumentError, "example source does not exist: #{relative_path}"
    end

    Code.require_file(source)
  end
end
