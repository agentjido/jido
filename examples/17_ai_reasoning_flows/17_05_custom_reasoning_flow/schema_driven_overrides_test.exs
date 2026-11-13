Code.require_file("schema_driven_overrides.ex", __DIR__)

defmodule Jido.Examples.AI.SchemaDrivenOverridesTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.SchemaOverrides.{Agent, Reasoning}

  test "reasoning defaults are visible on the derived route" do
    assert [%{handler: %{target: Reasoning}, defaults: %{greeting: "Welcome", punctuation: "!"}}] =
             Agent.definition().routes
  end

  test "a request can use or replace one schema default" do
    agent = Agent.instantiate!(id: "schema-ai-#{System.unique_integer([:positive])}")

    assert {:ok, _agent, [%Jido.Agent.Directive.Reply{signal: configured}]} =
             Agent.cmd(agent, Agent.request_signal!(%{input: "Ada"}))

    assert configured.data == %{output: "Welcome, Ada!"}

    assert {:ok, _agent, [%Jido.Agent.Directive.Reply{signal: overridden}]} =
             Agent.cmd(
               agent,
               Agent.request_signal!(%{input: "Ada", greeting: "Good morning"})
             )

    assert overridden.data == %{output: "Good morning, Ada!"}
  end

  test "unknown reasoning input is rejected" do
    assert {:error, _} = Agent.preflight(%{input: "Ada", unknown: true})
  end
end
