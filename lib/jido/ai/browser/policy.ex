defmodule Jido.AI.Browser.Policy do
  @moduledoc false

  @max_url_bytes 2_048
  @dns_name ~r/\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i
  @scoped_path ~r/\A\/[a-zA-Z0-9_~.\/\-]*\z/

  def parse(url) do
    with true <- safe_url_text?(url),
         {:ok, %URI{scheme: scheme, host: host, userinfo: nil, port: port} = uri} <- URI.new(url),
         true <- valid_host?(host),
         true <- {scheme, port} in [{"https", 443}, {"http", 80}] do
      {:ok, %{uri | host: String.downcase(host), path: uri.path || "/", fragment: nil}}
    else
      _ -> {:error, :invalid_url}
    end
  end

  def redirect(uri, location) do
    with true <- safe_url_text?(location),
         {:ok, reference} <- URI.new(location),
         false <- String.starts_with?(location, "//") and is_nil(reference.host) do
      uri |> URI.merge(reference) |> URI.to_string() |> parse()
    else
      _ -> {:error, :invalid_redirect}
    end
  end

  def allowed?(uri, agent_rules, host_rules) do
    matches?(uri, agent_rules) and matches?(uri, host_rules)
  end

  def normalize_rules(rules) when is_list(rules) and rules != [] do
    if not List.improper?(rules) and Enum.all?(rules, &valid_rule?/1) do
      {:ok, Enum.map(rules, &Map.update!(&1, "host", fn host -> String.downcase(host) end))}
    else
      {:error, :invalid_allowlist}
    end
  end

  def normalize_rules(_rules), do: {:error, :invalid_allowlist}

  defp valid_rule?(%{"host" => host, "path_prefix" => prefix} = rule) when map_size(rule) == 2 do
    valid_host?(host) and scoped_path?(prefix) and String.ends_with?(prefix, "/")
  end

  defp valid_rule?(_rule), do: false

  defp matches?(uri, rules) do
    Enum.any?(rules, fn %{"host" => host, "path_prefix" => prefix} ->
      uri.host == host and
        (prefix == "/" or (scoped_path?(uri.path) and String.starts_with?(uri.path, prefix)))
    end)
  end

  defp scoped_path?(path) do
    is_binary(path) and Regex.match?(@scoped_path, path) and
      not String.contains?(path, "//") and
      not Enum.any?(String.split(path, "/"), &(&1 in [".", ".."]))
  end

  defp valid_host?(host), do: is_binary(host) and byte_size(host) <= 253 and Regex.match?(@dns_name, host)

  defp safe_url_text?(url) do
    is_binary(url) and byte_size(url) in 1..@max_url_bytes and
      Regex.match?(~r/\A[\x21-\x7e]+\z/, url) and
      not String.contains?(url, "\\") and
      not Regex.match?(~r/%(?![\da-f]{2})|%(?:[01][\da-f]|7f)/i, url)
  end
end
