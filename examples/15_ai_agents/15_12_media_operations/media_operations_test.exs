Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("media_actions.ex", __DIR__)
Code.require_file("media_operations.ex", __DIR__)

defmodule Jido.Examples.AI.MediaOperationsTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.MediaOperations
  alias Jido.Examples.Support.OfflineInferenceClient

  test "one Flow uses every offline media-operation boundary" do
    assert {:ok, result} =
             Jido.Exec.run(
               MediaOperations,
               %{
                 document: "offline invoice bytes",
                 model: "offline:media",
                 prompt: "Blue square"
               },
               %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert result.image == %{bytes: 13, kind: :image}
    assert result.ocr == %{bytes: 21, text: "OFFLINE OCR"}
    assert result.speech.transcript == "offline transcript"
    assert result.speech.audio_bytes > 0
    assert result.video == %{bytes: 13, task_id: "offline-video-1"}
  end
end
