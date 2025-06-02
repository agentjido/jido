defmodule Jido.Signal.Router.Validator do
  @moduledoc """
  Validates router configuration and normalizes route specifications.
  """

  use ExDbug, enabled: false

  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Router.Route

  @default_priority 0
  @max_priority 100
  @min_priority -100

  @doc """
  Normalizes route specifications into Route structs.

  ## Parameters
    * `input` - One of:
      * Single Route struct
      * List of Route structs
      * List of route_spec tuples
      * {path, target} tuple where target is:
        * %Instruction{}
        * {adapter, opts}
        * [{adapter, opts}, ...]
      * {path, target, priority} tuple
      * {path, match_fn, target} tuple
      * {path, match_fn, target, priority} tuple

  ## Returns
    * `{:ok, [%Route{}]}` - List of normalized Route structs
    * `{:error, term()}` - If normalization fails
  """
  def normalize(%Route{} = route), do: {:ok, [route]}

  def normalize(routes) when is_list(routes) do
    routes
    |> Enum.reduce_while({:ok, []}, fn
      %Route{} = route, {:ok, acc} ->
        {:cont, {:ok, [route | acc]}}

      route_spec, {:ok, acc} ->
        case normalize_route_spec(route_spec) do
          {:ok, route} -> {:cont, {:ok, [route | acc]}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  def normalize(route_spec) when is_tuple(route_spec), do: normalize([route_spec])

  def normalize(invalid) do
    {:error,
     Error.validation_error("Invalid route specification format", %{
       route: invalid,
       expected_formats: [
         "%Route{}",
         "{path, target}",
         "{path, target, priority}",
         "{path, match_fn, target}",
         "{path, match_fn, target, priority}"
       ]
     })}
  end

  # Private helpers for normalization
  defp normalize_route_spec({path, target}) when is_binary(path) do
    case normalize_target(target) do
      {:ok, normalized_target} -> {:ok, %Route{path: path, target: normalized_target}}
      error -> error
    end
  end

  defp normalize_route_spec({path, target, priority})
       when is_binary(path) and is_integer(priority) do
    case normalize_target(target) do
      {:ok, normalized_target} ->
        {:ok, %Route{path: path, target: normalized_target, priority: priority}}

      error ->
        error
    end
  end

  defp normalize_route_spec({path, match_fn, target})
       when is_binary(path) and is_function(match_fn, 1) do
    case normalize_target(target) do
      {:ok, normalized_target} ->
        {:ok, %Route{path: path, target: normalized_target, match: match_fn}}

      error ->
        error
    end
  end

  defp normalize_route_spec({path, match_fn, target, priority})
       when is_binary(path) and is_function(match_fn, 1) and is_integer(priority) do
    case normalize_target(target) do
      {:ok, normalized_target} ->
        {:ok,
         %Route{
           path: path,
           target: normalized_target,
           match: match_fn,
           priority: priority
         }}

      error ->
        error
    end
  end

  defp normalize_route_spec(invalid) do
    {:error,
     Error.validation_error("Invalid route specification format", %{
       route: invalid,
       expected_formats: [
         "%Route{}",
         "{path, target}",
         "{path, target, priority}",
         "{path, match_fn, target}",
         "{path, match_fn, target, priority}"
       ]
     })}
  end

  defp normalize_target(target) do
    # Accept any term as a target - the router is agnostic about what it stores
    {:ok, target}
  end

  # defp normalize_target({adapter, _opts} = config) when is_atom(adapter), do: {:ok, config}

  # defp normalize_target(dispatch_configs) when is_list(dispatch_configs) do
  #   cond do
  #     # Handle invalid configs first
  #     not Enum.all?(dispatch_configs, &valid_config_format?/1) ->
  #       {:error,
  #        Error.validation_error("Invalid dispatch config list", %{
  #          dispatch_configs: dispatch_configs
  #        })}

  #     # Handle test adapters
  #     Enum.all?(dispatch_configs, &is_test_adapter?/1) ->
  #       {:ok, dispatch_configs}

  #     # Handle keyword list format
  #     Keyword.keyword?(dispatch_configs) ->
  #       normalized =
  #         Enum.map(dispatch_configs, fn {adapter, opts} ->
  #           adapter_name = adapter |> Atom.to_string() |> Macro.camelize()
  #           {Module.concat(Elixir, adapter_name), opts}
  #         end)

  #       {:ok, normalized}

  #     # For everything else, use Dispatch validation
  #     true ->
  #       case Dispatch.validate_opts(dispatch_configs) do
  #         {:ok, validated} ->
  #           {:ok, validated}

  #         {:error, reason} ->
  #           {:error, Error.validation_error("Invalid dispatch configuration", %{reason: reason})}
  #       end
  #   end
  # end

  # defp normalize_target(invalid) do
  #   {:error,
  #    Error.validation_error("Invalid route specification format", %{
  #      route: {nil, invalid},
  #      expected_formats: [
  #        "%Route{}",
  #        "{path, target}",
  #        "{path, target, priority}",
  #        "{path, match_fn, target}",
  #        "{path, match_fn, target, priority}"
  #      ]
  #    })}
  # end

  # defp valid_config_format?(config) do
  #   case config do
  #     {adapter, opts} when is_atom(adapter) and is_list(opts) -> true
  #     _ -> false
  #   end
  # end

  # defp is_test_adapter?({adapter, opts}) when is_atom(adapter) and is_list(opts) do
  #   adapter |> Atom.to_string() |> String.starts_with?("Test")
  # end

  # defp is_test_adapter?(_), do: false

  @doc """
  Validates a path string against the allowed format.

  ## Rules
  - Must be a string
  - Cannot contain consecutive dots (..)
  - Cannot have consecutive ** segments
  - Each segment must be either:
    - A valid identifier (alphanumeric + underscore + hyphen)
    - A single wildcard (*)
    - A double wildcard (**)

  ## Returns
  - `{:ok, path}` if valid
  - `{:error, reason}` if invalid
  """
  def validate_path(path) when is_binary(path) do
    cond do
      String.contains?(path, "..") ->
        {:error, Error.routing_error("Path cannot contain consecutive dots")}

      true ->
        segments = String.split(path, ".")

        # Check for consecutive ** segments first
        consecutive_wildcards? =
          segments
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.any?(fn [a, b] -> a == "**" and b == "**" end)

        if consecutive_wildcards? do
          {:error, Error.routing_error("Path cannot contain multiple wildcards")}
        else
          # Then validate each segment
          case Enum.find(segments, &(not valid_segment?(&1))) do
            nil ->
              {:ok, path}

            invalid ->
              cond do
                String.contains?(invalid, "**") ->
                  {:error, Error.routing_error("Path cannot contain '**' sequence")}

                String.contains?(invalid, "*") ->
                  {:error, Error.routing_error("Path cannot contain '*' within a segment")}

                true ->
                  {:error, Error.routing_error("Path contains invalid characters")}
              end
          end
        end
    end
  end

  def validate_path(_invalid) do
    {:error, Error.routing_error("Path must be a string")}
  end

  # A segment is valid if it's either:
  # - A single wildcard (*)
  # - A double wildcard (**)
  # - A valid identifier (alphanumeric + underscore + hyphen)
  defp valid_segment?("*"), do: true
  defp valid_segment?("**"), do: true
  defp valid_segment?(segment), do: String.match?(segment, ~r/^[a-zA-Z0-9_-]+$/)

  @doc """
  Validates that a target is a valid term.

  ## Valid Targets
  - Any term

  ## Returns
  - `{:ok, target}` - Always succeeds
  """
  def validate_target(target) do
    # Accept any term as a target - the router is agnostic about what it stores
    {:ok, target}
  end

  @doc """
  Validates that a match function returns boolean for a test signal.

  ## Parameters
  - match_fn: A function that takes a Signal struct and returns a boolean

  ## Returns
  - `{:ok, match_fn}` if valid
  - `{:error, reason}` if invalid
  """
  def validate_match(nil) do
    {:ok, nil}
  end

  def validate_match(match_fn) when is_function(match_fn, 1) do
    try do
      test_signal = %Signal{
        type: "",
        source: "",
        id: "",
        data: %{
          amount: 0,
          currency: "USD"
        }
      }

      case match_fn.(test_signal) do
        result when is_boolean(result) ->
          {:ok, match_fn}

        _other ->
          {:error, Error.routing_error("Match function must return a boolean")}
      end
    rescue
      _error ->
        {:error, Error.routing_error("Match function raised an error during validation")}
    end
  end

  def validate_match(_invalid) do
    {:error, Error.routing_error("Match must be a function that takes one argument")}
  end

  @doc """
  Validates that a priority value is within allowed bounds.

  ## Parameters
  - priority: An integer between -100 and 100, or nil for default priority

  ## Returns
  - `{:ok, priority}` if valid
  - `{:error, reason}` if invalid
  """
  def validate_priority(nil), do: {:ok, @default_priority}

  def validate_priority(priority) when is_integer(priority) do
    cond do
      priority > @max_priority ->
        {:error, Error.routing_error("Priority value exceeds maximum allowed")}

      priority < @min_priority ->
        {:error, Error.routing_error("Priority value below minimum allowed")}

      true ->
        {:ok, priority}
    end
  end

  def validate_priority(_invalid) do
    {:error, Error.routing_error("Priority must be an integer")}
  end
end
