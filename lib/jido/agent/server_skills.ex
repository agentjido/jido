defmodule Jido.Agent.Server.Skills do
  @moduledoc """
  Functions for building and managing skills in the agent server.
  """
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Skill

  @doc """
  Builds the skills for the agent server.

  This function takes a list of skills from the options and adds them to the server state.
  It also collects any routes and child_specs from the skills and adds them to the options.

  ## Parameters

  - `state` - The current server state
  - `opts` - The options for the server

  ## Returns

  - `{:ok, state, opts}` - The updated state and options
  - `{:error, reason}` - An error occurred
  """
  @dialyzer {:nowarn_function, build: 2}
  def build(%ServerState{} = state, opts) do
    case Keyword.get(opts, :skills) do
      nil ->
        {:ok, state, opts}

      skills when is_list(skills) ->
        build_skills(state, skills, opts)

      invalid ->
        {:error, "Skills must be a list, got: #{inspect(invalid)}"}
    end
  end

  defp build_skills(state, skills, opts) do
    # Initialize accumulators
    init_acc = {state, opts, [], []}

    # Process each skill
    case Enum.reduce_while(skills, init_acc, &process_skill/2) do
      {:error, reason} ->
        {:error, reason}

      {updated_state, updated_opts, routes, child_specs} ->
        # Merge routes and child_specs into options
        final_opts =
          updated_opts
          |> Keyword.update(:routes, routes, &(&1 ++ routes))
          |> Keyword.update(:child_specs, child_specs, &(child_specs ++ &1))

        {:ok, updated_state, final_opts}
    end
  end

  defp process_skill(skill, {state, opts, routes_acc, child_specs_acc}) do
    # Get the skill's opts_key
    opts_key = skill.opts_key()
    # Get the options for this skill from the main opts, defaulting to empty keyword list
    skill_opts = Keyword.get(opts, opts_key, [])
    # Validate the skill options against the skill's schema
    {:ok, validated_opts} = Skill.validate_opts(skill, skill_opts)
    # Update the agent's state with the validated options
    updated_agent =
      Map.update!(state.agent, :state, fn current_state ->
        Map.put(current_state, opts_key, validated_opts)
      end)

    # Call the skill's mount callback to allow it to transform the agent
    case skill.mount(updated_agent, validated_opts) do
      {:ok, mounted_agent} ->
        # Update the state with the skill and mounted agent
        updated_state = %{state | skills: [skill | state.skills], agent: mounted_agent}
        # Get routes from the skill's router function
        new_routes = skill.router(validated_opts)
        # Validate routes
        if is_list(new_routes) do
          # Get child_spec from the skill
          new_child_specs = List.wrap(skill.child_spec(validated_opts))

          # Continue processing with updated accumulators
          {:cont,
           {updated_state, opts, routes_acc ++ new_routes, child_specs_acc ++ new_child_specs}}
        else
          {:halt,
           {:error, "Skill #{skill.name()} returned invalid routes: #{inspect(new_routes)}"}}
        end

      {:error, reason} ->
        {:halt, {:error, "Failed to mount skill #{skill.name()}: #{inspect(reason)}"}}
    end
  end
end
