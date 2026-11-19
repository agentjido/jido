defmodule Jido.Examples.ContextMemory.LongRunning.OfflineClient do
  @behaviour Jido.AI.InferenceClient

  @impl true
  def generate_text("offline:archive-summary" = model, context, _options) do
    input = context.messages |> List.last() |> text() |> JSON.decode!()
    last = List.last(input["archived_turns"])
    response(model, context, ReqLLM.Context.assistant("Reviewed archived history through Turn #{last["turn"]}."), :stop)
  end

  def generate_text(model, context, _options) do
    current =
      context.messages
      |> Enum.reverse()
      |> Enum.take_while(&(&1.role != :user))

    user = context.messages |> Enum.reverse() |> Enum.find(&(&1.role == :user)) |> text()

    case {Enum.find(current, &(&1.role == :tool)), Regex.run(~r/^Recall turn (\d+)$/, user)} do
      {nil, [_, number]} ->
        call =
          ReqLLM.ToolCall.new("recall-#{number}", "recall_turn", JSON.encode!(%{number: String.to_integer(number)}))

        response(model, context, ReqLLM.Context.assistant("", tool_calls: [call]), :tool_calls)

      {%{metadata: %{tool_output: output}}, _request} ->
        response(model, context, ReqLLM.Context.assistant("Archive: " <> JSON.encode!(output)), :stop)

      {nil, nil} ->
        response(model, context, ReqLLM.Context.assistant("Recorded."), :stop)
    end
  end

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks),
      name != :generate_text do
    arguments = Macro.generate_arguments(arity, __MODULE__)

    @impl true
    def unquote(name)(unquote_splicing(arguments)), do: {:error, :unsupported_offline_operation}
  end

  defp text(message), do: Enum.map_join(message.content, & &1.text)

  defp response(model, context, message, reason) do
    {:ok,
     %ReqLLM.Response{
       id: "offline-transcript",
       model: model,
       context: ReqLLM.Context.append(context, message),
       message: message,
       finish_reason: reason
     }}
  end
end
