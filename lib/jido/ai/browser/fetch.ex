defmodule Jido.AI.Browser.Fetch do
  @moduledoc "Reads a page within the Agent and host allowlists."

  alias Jido.Joi

  use Jido.Action,
    id: "jido.ai/browser/fetch",
    name: "web_fetch",
    description: "Read the text of a web page and return its final URL.",
    schema: Joi.object(%{url: Joi.string()}),
    output_schema: Joi.map()

  @impl true
  def run(%{url: url}, context), do: Jido.AI.Browser.fetch(url, context)
end
