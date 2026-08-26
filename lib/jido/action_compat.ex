defmodule Jido.ActionCompat do
  @moduledoc false

  @jido_action_v3 Code.ensure_loaded?(Jido.Executable) and
                    function_exported?(Jido.Executable, :resolve, 1)

  @type major_version :: 2 | 3

  if @jido_action_v3 do
    @doc false
    @spec major_version() :: major_version()
    def major_version, do: 3

    @doc false
    @spec v3?() :: boolean()
    def v3?, do: true

    @doc false
    @spec action?(module()) :: boolean()
    def action?(module) when is_atom(module) do
      with {:module, _} <- Code.ensure_compiled(module),
           {:ok, %{kind: :action, target: ^module} = executable} <- resolve(module),
           :ok <- apply(Jido.Executable, :validate, [executable]) do
        true
      else
        _error -> false
      end
    end

    def action?(_module), do: false

    @doc false
    @spec action_metadata(module()) :: map()
    def action_metadata(module) do
      %{
        name: optional_metadata(module, :name) || Atom.to_string(module),
        description: optional_metadata(module, :description),
        category: optional_metadata(module, :category),
        tags: optional_metadata(module, :tags)
      }
    end

    @doc false
    @spec resolve(module()) :: term()
    def resolve(module), do: apply(Jido.Executable, :resolve, [module])

    defp optional_metadata(module, function) do
      if function_exported?(module, function, 0), do: apply(module, function, []), else: nil
    end
  else
    @doc false
    @spec major_version() :: major_version()
    def major_version, do: 2

    @doc false
    @spec v3?() :: boolean()
    def v3?, do: false

    @doc false
    @spec action?(module()) :: boolean()
    def action?(module) when is_atom(module) do
      match?({:module, _}, Code.ensure_compiled(module)) and
        function_exported?(module, :__action_metadata__, 0)
    end

    def action?(_module), do: false

    @doc false
    @spec action_metadata(module()) :: map()
    def action_metadata(module) do
      module
      |> apply(:__action_metadata__, [])
      |> normalize_metadata()
    end

    @doc false
    @spec resolve(module()) :: {:ok, module()} | {:error, :not_an_action}
    def resolve(module) do
      if action?(module), do: {:ok, module}, else: {:error, :not_an_action}
    end

    defp normalize_metadata(metadata) when is_list(metadata) do
      if Keyword.keyword?(metadata), do: Map.new(metadata), else: %{}
    end

    defp normalize_metadata(metadata) when is_map(metadata), do: metadata
    defp normalize_metadata(_metadata), do: %{}
  end
end
