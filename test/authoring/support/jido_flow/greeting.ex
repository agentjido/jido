defmodule Jido.Test.Flow.Authoring.Greeting.Normalize do
  use Jido.Action,
    name: "authoring_normalize_name",
    schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{name: Jido.Joi.string()})

  @impl true
  def run(%{name: name}, _context), do: {:ok, %{name: String.trim(name)}}
end

defmodule Jido.Test.Flow.Authoring.Greeting.Greet do
  use Jido.Action,
    name: "authoring_greet",
    schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{message: Jido.Joi.string()})

  @impl true
  def run(%{name: name}, %{prefix: prefix}), do: {:ok, %{message: prefix <> ", " <> name <> "!"}}
end

defmodule Jido.Test.Flow.Authoring.Greeting.Flow do
  use Jido.Flow,
    name: "authoring_greeting",
    schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{message: Jido.Joi.string()})

  flow do
    step "normalize",
      action: Jido.Test.Flow.Authoring.Greeting.Normalize,
      params: %{name: input(:name)}

    step "greet",
      action: Jido.Test.Flow.Authoring.Greeting.Greet,
      params: %{name: result("normalize", :name)}

    output result("greet")
  end
end
