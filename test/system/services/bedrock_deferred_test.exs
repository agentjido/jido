defmodule JidoTest.System.Services.BedrockDeferredTest do
  use ExUnit.Case, async: false

  @moduletag :service
  @moduletag skip: "Bedrock service pressure is deferred pending bedrock-kv/bedrock#319"

  test "the strict service profile is active" do
    flunk("remove the defer marker only after the upstream blocker is resolved")
  end
end
