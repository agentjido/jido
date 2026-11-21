defmodule Jido.Statechart.W3CTest do
  use ExUnit.Case, async: false

  alias Jido.Statechart.{Conformance, SCXML}

  @moduletag :scxml_conformance
  @fixtures Path.expand("../../../fixtures/statechart/w3c", __DIR__)
  @manifest Path.join(@fixtures, "manifest.xml")
  @external_resource @manifest

  {{nil, "assertions"}, _, assertions} = @manifest |> File.read!() |> SCXML.read!()

  entries =
    for {{nil, "assert"}, attributes, tests} <- assertions,
        {{nil, "test"}, _, files} <- tests,
        {{nil, "start"}, start, _} <- files do
      {{nil, "specnum"}, section} = List.keyfind!(attributes, {nil, "specnum"}, 0)
      {{nil, "uri"}, entry} = List.keyfind!(start, {nil, "uri"}, 0)
      {entry, section}
    end

  if entries == [], do: raise("No SCXML start entries in #{@manifest}")

  for {entry, section} <- entries do
    path = Path.join(@fixtures, entry)

    case section do
      "5.8" -> @tag skip: "Requires scripting"
      "B.2" -> @tag skip: "Requires ECMAScript"
      _section -> :ok
    end

    case entry do
      "198/test198.txml" ->
        test "#{entry} passes with the origintype translation" do
          assert Conformance.w3c(unquote(path)) == :ok
        end

      "352/test352.txml" ->
        test "#{entry} reaches fail because it expects the SCXML event processor URI" do
          assert Conformance.w3c(unquote(path)) == {:fail, :fixture_reached_fail}
        end

      _entry ->
        test "#{entry} passes in a live Agent" do
          assert Conformance.w3c(unquote(path)) == :ok
        end
    end
  end
end
