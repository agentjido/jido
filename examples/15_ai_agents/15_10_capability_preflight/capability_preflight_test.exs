Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("capability_actions.ex", __DIR__)
Code.require_file("capability_preflight.ex", __DIR__)

defmodule Jido.Examples.AI.CapabilityPreflightTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.CapabilityPreflight
  alias Jido.Examples.Support.OfflineInferenceClient

  test "required capabilities pass before the offline model call" do
    input = %{
      model: "offline:multimodal",
      profile: %{image_input: true, text: true, tools: false},
      prompt: "Describe the image.",
      required: [:text, :image_input]
    }

    assert {:ok,
            %{
              checked: [:text, :image_input],
              model: "offline:multimodal",
              output: "Capability preflight passed."
            }} =
             Jido.Exec.run(CapabilityPreflight, input, %{
               jido_ai_inference_client: OfflineInferenceClient
             })
  end

  test "a missing capability stops the Flow before inference" do
    input = %{
      model: "offline:text-only",
      profile: %{image_input: false, text: true},
      prompt: "Describe the image.",
      required: [:text, :image_input]
    }

    assert {:error, error} =
             Jido.Exec.run(CapabilityPreflight, input, %{
               jido_ai_inference_client: OfflineInferenceClient
             })

    assert Exception.message(error) =~ "model capability preflight failed"
  end
end
