defmodule Jido.Examples.Plugins.CommitNotifier.Notify do
  @moduledoc "Requests one notification after a successful state commit."
  use Jido.Agent.Directive

  @schema Jido.Joi.struct(
            __MODULE__,
            %{message: Jido.Joi.string() |> Jido.Joi.min(1)},
            coerce: true
          )

  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.Plugins.CommitNotifier.Plugin do
  @moduledoc "Owns a commit counter, a post-commit hook, and Notify dispatch."

  use Jido.Plugin, option_keys: [agent_server: [:observer]]

  alias Jido.Examples.Plugins.CommitNotifier.Notify

  @impl true
  def state_spec(_opts), do: {:notifications, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def directives(_opts), do: [Notify]

  @impl true
  def reduce(reduction, _opts) do
    count = Enum.count(reduction.directives, &match?(%Notify{}, &1))
    {:ok, reduction.plugin_state + count}
  end

  @impl true
  def after_commit(_runtime, commit, opts) do
    send(Keyword.fetch!(opts, :observer), {
      :commit_hook,
      commit.turn_id,
      commit.state_version,
      commit.plugin_state
    })

    :ok
  end

  @impl true
  def dispatch(_runtime, %Notify{message: message}, context, opts) do
    send(Keyword.fetch!(opts, :observer), {
      :notification_dispatched,
      context.turn_id,
      context.state_version,
      context.plugin_state,
      message
    })

    :ok
  end
end

defmodule Jido.Examples.Plugins.CommitNotifier.Agent do
  @moduledoc "Commits a message before the Plugin notification runs."

  use Jido.Agent,
    name: "plugin_commit_notifier",
    plugins: [Jido.Examples.Plugins.CommitNotifier.Plugin]

  alias Jido.Examples.Plugins.CommitNotifier.Notify

  state do
    schema Jido.Joi.object(%{last_message: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/examples/plugins/commit-notifier"

    route "examples.plugins.commit_notifier.send", as: :send_notification do
      action %{message: message},
        schema: Jido.Joi.object(%{message: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | last_message: message}, [%Notify{message: message}]}
      end
    end
  end
end
