defmodule Jido.AI.Skill do
  @moduledoc """
  Loads trusted `SKILL.md` instructions through `Jido.AI.ToolSource`.

  A skill root contains one directory for each skill:

      .agents/skills/
      └── code-review/
          └── SKILL.md

  Add the source to the trusted execution context:

      source = Jido.AI.Skill.source([".agents/skills"])

      MyAgent.cmd(agent, request,
        context: %{jido_ai_tool_sources: [source]}
      )

  The source adds one `load_skill` tool. The tool description contains the
  available skill names and descriptions. A tool call returns the selected
  Markdown body.

  Only `SKILL.md` is supported. This module does not inspect or execute scripts,
  resources, references, or other files in a skill directory.
  """

  @behaviour Jido.AI.ToolSource

  @tool_name "load_skill"
  @max_name_bytes 64
  @max_description_bytes 1_024
  @name_pattern ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  @typedoc "A discovered skill summary."
  @type summary :: %{name: String.t(), description: String.t()}

  @doc "Builds a portable tool source for trusted skill roots."
  @spec source([Path.t()]) :: Jido.AI.ToolSource.spec()
  def source(roots) when is_list(roots) do
    case normalize_roots(roots) do
      {:ok, roots} -> {__MODULE__, %{roots: roots}}
      {:error, reason} -> raise ArgumentError, "invalid skill roots: #{inspect(reason)}"
    end
  end

  @doc "Discovers valid skills one directory level below each root."
  @spec discover([Path.t()]) :: {:ok, [summary()]} | {:error, term()}
  def discover(roots) when is_list(roots) do
    with {:ok, skills} <- discover_skills(roots) do
      {:ok, Enum.map(skills, &Map.take(&1, [:name, :description]))}
    end
  end

  def discover(_roots), do: {:error, :invalid_skill_roots}

  @doc "Loads one discovered skill by name."
  @spec load([Path.t()], String.t()) ::
          {:ok, %{name: String.t(), description: String.t(), instructions: String.t()}}
          | {:error, term()}
  def load(roots, name) when is_list(roots) and is_binary(name) do
    with {:ok, skills} <- discover_skills(roots) do
      case Enum.find(skills, &(&1.name == name)) do
        nil -> {:error, {:unknown_skill, name}}
        skill -> {:ok, Map.take(skill, [:name, :description, :instructions])}
      end
    end
  end

  def load(_roots, _name), do: {:error, :invalid_skill_request}

  @impl Jido.AI.ToolSource
  def list_tools(config, _context) do
    with {:ok, roots} <- config_roots(config),
         {:ok, skills} <- discover(roots) do
      if skills == [], do: {:ok, []}, else: {:ok, [tool_definition(skills)]}
    end
  end

  @impl Jido.AI.ToolSource
  def run_tool(%{name: @tool_name, arguments: arguments}, config, _context) do
    with {:ok, roots} <- config_roots(config),
         {:ok, name} <- skill_name(arguments) do
      load(roots, name)
    end
  end

  def run_tool(%{name: name}, _config, _context), do: {:error, {:unknown_skill_tool, name}}
  def run_tool(_call, _config, _context), do: {:error, :invalid_skill_tool_call}

  defp tool_definition(skills) do
    catalog = Enum.map_join(skills, "\n", &"- #{&1.name}: #{one_line(&1.description)}")

    %{
      name: @tool_name,
      description: """
      Load the instructions for one available skill. Use a skill when its description matches the task.

      Available skills:
      #{catalog}
      """,
      parameter_schema: [
        name: [type: :string, required: true, doc: "The exact available skill name"]
      ]
    }
  end

  defp discover_skills(roots) do
    with {:ok, roots} <- normalize_roots(roots),
         {:ok, skills} <- scan_roots(roots),
         :ok <- unique_names(skills) do
      {:ok, Enum.sort_by(skills, & &1.name)}
    end
  end

  defp normalize_roots(roots) when is_list(roots) do
    Enum.reduce_while(roots, {:ok, []}, fn
      root, {:ok, normalized} when is_binary(root) and root != "" ->
        {:cont, {:ok, [Path.expand(root) | normalized]}}

      _root, _result ->
        {:halt, {:error, :invalid_skill_roots}}
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp normalize_roots(_roots), do: {:error, :invalid_skill_roots}

  defp scan_roots(roots) do
    Enum.reduce_while(roots, {:ok, []}, fn root, {:ok, skills} ->
      case scan_root(root) do
        {:ok, found} -> {:cont, {:ok, skills ++ found}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp scan_root(root) do
    case File.ls(root) do
      {:ok, children} ->
        children
        |> Enum.sort()
        |> Enum.map(&Path.join([root, &1, "SKILL.md"]))
        |> Enum.filter(&File.regular?/1)
        |> Enum.reduce_while({:ok, []}, fn path, {:ok, skills} ->
          case read_skill(path) do
            {:ok, skill} -> {:cont, {:ok, [skill | skills]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, skills} -> {:ok, Enum.reverse(skills)}
          error -> error
        end

      {:error, reason} ->
        {:error, {:invalid_skill_root, root, reason}}
    end
  end

  defp read_skill(path) do
    result =
      with {:ok, content} <- File.read(path),
           true <- String.valid?(content),
           {:ok, frontmatter, instructions} <- split_document(content),
           {:ok, metadata} <- YamlElixir.read_from_string(frontmatter),
           true <- is_map(metadata),
           {:ok, skill} <- validate_metadata(metadata, Path.basename(Path.dirname(path))) do
        {:ok, Map.put(skill, :instructions, instructions)}
      else
        false -> {:error, :invalid_utf8_or_frontmatter}
        {:error, error} when is_exception(error) -> {:error, {:invalid_yaml, Exception.message(error)}}
        {:error, reason} -> {:error, reason}
      end

    case result do
      {:ok, skill} -> {:ok, skill}
      {:error, reason} -> {:error, {:invalid_skill_file, path, reason}}
    end
  end

  defp split_document(content) do
    case String.split(content, ~r/\r?\n/, trim: false) do
      ["---" | lines] ->
        case Enum.split_while(lines, &(&1 != "---")) do
          {_frontmatter, []} ->
            {:error, :unterminated_frontmatter}

          {frontmatter, ["---" | instructions]} ->
            {:ok, Enum.join(frontmatter, "\n"), Enum.join(instructions, "\n")}
        end

      _other ->
        {:error, :missing_frontmatter}
    end
  end

  defp validate_metadata(metadata, directory_name) do
    name = Map.get(metadata, "name")
    description = Map.get(metadata, "description")

    cond do
      not is_binary(name) -> {:error, :name_required}
      name == "" or byte_size(name) > @max_name_bytes -> {:error, :invalid_name}
      not Regex.match?(@name_pattern, name) -> {:error, :invalid_name}
      name != directory_name -> {:error, {:name_must_match_directory, directory_name}}
      not is_binary(description) or description == "" -> {:error, :description_required}
      byte_size(description) > @max_description_bytes -> {:error, :description_too_large}
      true -> {:ok, %{name: name, description: description}}
    end
  end

  defp unique_names(skills) do
    case skills |> Enum.frequencies_by(& &1.name) |> Enum.find(fn {_name, count} -> count > 1 end) do
      nil -> :ok
      {name, _count} -> {:error, {:duplicate_skill, name}}
    end
  end

  defp config_roots(config) when is_map(config) do
    case Map.get(config, :roots, Map.get(config, "roots")) do
      roots when is_list(roots) -> {:ok, roots}
      _other -> {:error, :invalid_skill_source}
    end
  end

  defp config_roots(_config), do: {:error, :invalid_skill_source}

  defp skill_name(arguments) when is_map(arguments) do
    case Map.get(arguments, :name, Map.get(arguments, "name")) do
      name when is_binary(name) and name != "" -> {:ok, name}
      _other -> {:error, :invalid_skill_name}
    end
  end

  defp skill_name(_arguments), do: {:error, :invalid_skill_name}

  defp one_line(description), do: description |> String.replace(~r/\s+/u, " ") |> String.trim()
end
