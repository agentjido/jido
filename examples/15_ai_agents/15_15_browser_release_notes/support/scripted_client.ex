defmodule Jido.Examples.AI.BrowserReleaseNotes.ScriptedClient do
  @moduledoc false

  @behaviour Jido.AI.InferenceClient

  alias Jido.Examples.Support.OfflineInferenceClient, as: Offline
  alias ReqLLM.{Context, Response, ToolCall}

  @impl true
  def generate_text(model, context, _options) do
    {message, finish_reason} = next_message(List.last(Context.to_list(context)))

    {:ok,
     %Response{
       id: "offline-release-note",
       model: model,
       context: Context.append(context, message),
       finish_reason: finish_reason,
       message: message,
       usage: %{input_tokens: 8, output_tokens: 4}
     }}
  end

  defp next_message(%{role: :tool, metadata: %{tool_output: %{"url" => url, "text" => text}}}) do
    {Context.assistant("#{text} Source: #{url}"), :stop}
  end

  defp next_message(%{role: :tool, metadata: %{tool_output: %{"status" => "error"}}}) do
    {Context.assistant("The browser tool could not read this page."), :stop}
  end

  defp next_message(%{role: :user, content: [%{type: :text, text: url}]}) do
    call = ToolCall.new("read-release-note", "web_fetch", JSON.encode!(%{url: url}))
    {Context.assistant("", tool_calls: [call]), :tool_calls}
  end

  for {name, arity} <- Jido.AI.InferenceClient.behaviour_info(:callbacks), name != :generate_text do
    args = Macro.generate_arguments(arity, __MODULE__)
    @impl true
    defdelegate unquote(name)(unquote_splicing(args)), to: Offline
  end
end
