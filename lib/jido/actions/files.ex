defmodule Jido.Actions.Files do
  @moduledoc """
  Comprehensive file manipulation actions for the Jido SDK.

  This module provides actions for:
  - File operations (read, write, copy, move, delete)
  - Directory operations (create, remove, list)
  - Path manipulation and verification
  - File metadata operations
  - Content manipulation
  """

  alias Jido.Action

  defmodule WriteFile do
    @moduledoc "Writes content to a file, creating parent directories if needed"
    use Action,
      name: "write_file",
      description: "Writes content to a file, optionally creating parent directories",
      schema: [
        path: [type: :string, required: true, doc: "Path to the file to be written"],
        content: [type: :string, required: true, doc: "Content to be written to the file"],
        create_dirs: [
          type: :boolean,
          default: false,
          doc: "Create parent directories if they don't exist"
        ],
        mode: [
          type: {:in, [:write, :append]},
          default: :write,
          doc: "Write mode - :write overwrites, :append adds to end"
        ]
      ]

    @impl true
    def run(%{path: path, content: content, create_dirs: create_dirs, mode: mode}, _context) do
      if create_dirs, do: File.mkdir_p(Path.dirname(path))

      case write_with_mode(path, content, mode) do
        :ok -> {:ok, %{path: path, bytes_written: byte_size(content)}}
        {:error, reason} -> {:error, "Failed to write file: #{inspect(reason)}"}
      end
    end

    defp write_with_mode(path, content, :write), do: File.write(path, content)
    defp write_with_mode(path, content, :append), do: File.write(path, content, [:append])
  end

  defmodule MakeDirectory do
    @moduledoc "Creates a directory and optionally its parent directories"
    use Action,
      name: "make_directory",
      description: "Creates a new directory, optionally creating parent directories",
      schema: [
        path: [type: :string, required: true, doc: "Path to the directory to create"],
        recursive: [
          type: :boolean,
          default: false,
          doc: "Create parent directories if they don't exist"
        ]
      ]

    @impl true
    def run(%{path: path, recursive: true}, _context) do
      case File.mkdir_p(path) do
        :ok -> {:ok, %{path: path}}
        {:error, reason} -> {:error, "Failed to create directory: #{inspect(reason)}"}
      end
    end

    def run(%{path: path, recursive: false}, _context) do
      case File.mkdir(path) do
        :ok -> {:ok, %{path: path}}
        {:error, reason} -> {:error, "Failed to create directory: #{inspect(reason)}"}
      end
    end
  end

  defmodule ListDirectory do
    @moduledoc "Lists contents of a directory with optional filtering"
    use Action,
      name: "list_directory",
      description: "Lists directory contents with optional pattern matching",
      schema: [
        path: [type: :string, required: true, doc: "Path to the directory to list"],
        pattern: [
          type: :string,
          doc: "Optional glob pattern for filtering files",
          required: false
        ],
        recursive: [
          type: :boolean,
          default: false,
          doc: "Include subdirectories recursively"
        ]
      ]

    @impl true
    def run(%{path: path, pattern: pattern, recursive: recursive}, _context)
        when is_binary(pattern) do
      result =
        case recursive do
          true -> Path.wildcard(Path.join(path, pattern))
          false -> Path.wildcard(Path.join(path, pattern)) |> Enum.reject(&File.dir?/1)
        end

      {:ok, %{entries: result}}
    end

    def run(%{path: path, recursive: recursive}, _context) do
      case recursive do
        true ->
          case File.ls(path) do
            {:ok, entries} -> {:ok, %{entries: entries}}
            {:error, reason} -> {:error, "Failed to list directory: #{inspect(reason)}"}
          end

        false ->
          case File.ls(path) do
            {:ok, entries} ->
              files = Enum.reject(entries, &File.dir?(Path.join(path, &1)))
              {:ok, %{entries: files}}

            {:error, reason} ->
              {:error, "Failed to list directory: #{inspect(reason)}"}
          end
      end
    end
  end

  defmodule DeleteFile do
    @moduledoc "Deletes a file or directory"
    use Action,
      name: "delete_file",
      description: "Deletes a file or directory with optional recursive deletion",
      schema: [
        path: [type: :string, required: true, doc: "Path to delete"],
        recursive: [
          type: :boolean,
          default: false,
          doc: "Recursively delete directories and contents"
        ],
        force: [
          type: :boolean,
          default: false,
          doc: "Force deletion even if file is read-only"
        ]
      ]

    @impl true
    def run(%{path: path, recursive: true}, _context) do
      case File.rm_rf(path) do
        {:ok, paths} ->
          {:ok, %{deleted: paths}}

        {:error, reason, paths} ->
          {:error, "Failed to delete some paths: #{inspect(reason)}, deleted: #{inspect(paths)}"}
      end
    end

    def run(%{path: path, recursive: false, force: force}, _context) do
      result =
        if force do
          case File.rm_rf(path) do
            {:ok, _paths} -> :ok
            {:error, reason, _paths} -> {:error, reason}
          end
        else
          File.rm(path)
        end

      case result do
        :ok -> {:ok, %{path: path}}
        {:error, reason} -> {:error, "Failed to delete: #{inspect(reason)}"}
      end
    end
  end

  defmodule ReadFile do
    @moduledoc false
    use Action,
      name: "read_file",
      description: "Reads content from a file",
      schema: [
        path: [type: :string, required: true, doc: "Path to the file to be read"]
      ]

    @impl true
    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{path: path}, _context) do
      case File.read(path) do
        {:ok, content} -> {:ok, %{path: path, content: content}}
        {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
      end
    end
  end

  defmodule CopyFile do
    @moduledoc false
    use Action,
      name: "copy_file",
      description: "Copies a file from source to destination",
      schema: [
        source: [type: :string, required: true, doc: "Path to the source file"],
        destination: [type: :string, required: true, doc: "Path to the destination file"]
      ]

    @impl true
    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{source: source, destination: destination}, _context) do
      case File.copy(source, destination) do
        {:ok, bytes_copied} ->
          {:ok, %{source: source, destination: destination, bytes_copied: bytes_copied}}

        {:error, reason} ->
          {:error, "Failed to copy file: #{inspect(reason)}"}
      end
    end
  end

  defmodule MoveFile do
    @moduledoc false
    use Action,
      name: "move_file",
      description: "Moves a file from source to destination",
      schema: [
        source: [type: :string, required: true, doc: "Path to the source file"],
        destination: [type: :string, required: true, doc: "Path to the destination file"]
      ]

    @impl true
    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{source: source, destination: destination}, _context) do
      case File.rename(source, destination) do
        :ok -> {:ok, %{source: source, destination: destination}}
        {:error, reason} -> {:error, "Failed to move file: #{inspect(reason)}"}
      end
    end
  end
end
