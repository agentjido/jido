defmodule Jido.AI.Browser.Search do
  @moduledoc "Searches for pages within the Agent and host allowlists."

  alias Jido.Joi

  use Jido.Action,
    id: "jido.ai/browser/search",
    name: "search_web",
    description: "Find web pages and return their titles, URLs, and snippets.",
    schema: Joi.object(%{query: Joi.string()}),
    output_schema: Joi.map()

  @impl true
  def run(%{query: query}, context), do: Jido.AI.Browser.search(query, context)
end
