alias Jido.Examples.Factory.IEx, as: FactoryChat

mode =
  case System.argv() do
    [] ->
      :conversation

    ["conversation"] ->
      :conversation

    ["workshop"] ->
      :workshop

    ["departments"] ->
      :departments

    _ ->
      raise ArgumentError,
            "Use: mix run lib/examples/06_factory/chat.exs [conversation|workshop|departments]"
  end

env_file = Path.expand("../../../.env", __DIR__)

case Dotenvy.source([env_file, System.get_env()]) do
  {:ok, variables} -> System.put_env(variables)
  {:error, _reason} -> raise "Cannot load the project .env file. Check its format."
end

{:ok, session} = FactoryChat.start(mode)

try do
  FactoryChat.chat(session)
after
  FactoryChat.stop(session)
end
