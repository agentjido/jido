defmodule JidoTest do
  use ExUnit.Case
  doctest Jido

  test "greets the world" do
    assert Jido.hello() == :world
  end
end
