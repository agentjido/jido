Code.require_file("../../support/loader.exs", __DIR__)

JidoTest.Examples.Loader.require_source!("00_quick_start/00_02_schema_driven_overrides/schema_driven_overrides.ex")

defmodule JidoTest.Examples.AI.SchemaDrivenOverridesTest do
  use Jido.Test.Case, async: true

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("00_quick_start/00_02_schema_driven_overrides/schema_driven_overrides.ex")

    :ok
  end

  alias Jido.Examples.AI.SchemaOverrides.{Agent, Reasoning}

  test "reasoning defaults are visible on the derived route" do
    assert [%{handler: %{target: Reasoning}, defaults: %{greeting: "Welcome", punctuation: "!"}}] =
             Agent.definition().routes
  end

  test "a request can use or replace one schema default" do
    agent = Agent.instantiate!(id: unique_id("schema-ai"))

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
