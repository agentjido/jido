defmodule Jido.Actions.Files do
  @moduledoc """
  Actions for file-related operations in workflows.

  This module provides a set of actions for common file operations:
  - WriteFile: Writes content to a file
  - ReadFile: Reads content from a file
  - CopyFile: Copies a file from source to destination
  - MoveFile: Moves a file from source to destination

  Each action is implemented as a separate submodule and follows the Jido.Action behavior.
  """

  alias Jido.Action

  defmodule WriteFile do
    @moduledoc false
    use Action,
      name: "write_file",
      description: "Writes content to a file",
      schema: [
        path: [type: :string, required: true, doc: "Path to the file to be written"],
        content: [type: :string, required: true, doc: "Content to be written to the file"]
      ]

    @impl true
    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{path: path, content: content}, _context) do
      case File.write(path, content) do
        :ok -> {:ok, %{path: path, bytes_written: byte_size(content)}}
        {:error, reason} -> {:error, "Failed to write file: #{inspect(reason)}"}
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
