defmodule Jido.Agent.Interface do
  @moduledoc false

  alias Jido.Agent.Authoring

  @signal_keys [:source, :id, :subject, :time, :datacontenttype, :dataschema, :extensions]

  def signal(config, input, opts) when is_map(input) and not is_struct(input) do
    with {:ok, envelope} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(envelope, @signal_keys) do
      Jido.Signal.new(
        config.path,
        input,
        Map.to_list(Map.put_new(envelope, :source, config.source))
      )
    end
  end

  def signal(_config, _input, _opts),
    do: Authoring.error("Interface input must be a plain map")
end
