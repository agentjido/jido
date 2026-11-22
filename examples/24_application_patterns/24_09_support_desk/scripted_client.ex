defmodule Jido.Examples.Patterns.SupportDesk.ScriptedClient do
  @moduledoc "Runs the example without a model provider."

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline
  alias ReqLLM.{Context, Response, ToolCall}

  @impl true
  def generate_text(model, context, options) do
    {message, finish_reason} =
      cond do
        Keyword.get(options, :offline_response) == "unsafe" ->
          {Context.assistant("Your ticket is resolved."), :stop}

        List.last(Context.to_list(context)).role == :tool ->
          {Context.assistant("Check the printer cable."), :stop}

        true ->
          call = ToolCall.new("desk-tool-1", "troubleshoot_printer", "{}")
          {Context.assistant("", tool_calls: [call]), :tool_calls}
      end

    {:ok,
     %Response{
       id: "offline-support-desk",
       model: model,
       context: Context.append(context, message),
       finish_reason: finish_reason,
       message: message,
       usage: %{input_tokens: 8, output_tokens: 4}
     }}
  end

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks), name != :generate_text do
    args = Macro.generate_arguments(arity, __MODULE__)
    @impl true
    defdelegate unquote(name)(unquote_splicing(args)), to: Offline
  end
end
