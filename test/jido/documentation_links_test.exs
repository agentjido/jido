defmodule JidoTest.DocumentationLinksTest do
  use ExUnit.Case, async: true

  test "current guide links point to source paths that exist" do
    guides = Path.wildcard("guides/*.md") ++ Path.wildcard("guides/*.livemd")

    broken =
      Enum.flat_map(guides, fn guide ->
        body = File.read!(guide)

        relative =
          ~r/\]\(([^)]+)\)/
          |> Regex.scan(body, capture: :all_but_first)
          |> Enum.map(&hd/1)
          |> Enum.reject(&external_or_generated?/1)
          |> Enum.reject(fn target ->
            target = target |> String.split("#", parts: 2) |> hd()
            File.exists?(Path.expand(target, Path.dirname(guide)))
          end)

        current_branch =
          ~r{https://github\.com/agentjido/jido/(?:tree|blob)/release/v3/([^\s)#]+)}
          |> Regex.scan(body, capture: :all_but_first)
          |> Enum.map(&hd/1)
          |> Enum.reject(&File.exists?/1)

        stale_branch =
          if body =~ ~r{https://github\.com/agentjido/jido/(?:tree|blob)/v3-spike/},
            do: ["v3-spike link"],
            else: []

        Enum.map(relative ++ current_branch ++ stale_branch, &{guide, &1})
      end)

    assert broken == []
  end

  test "AgentServer design evidence uses stable source paths" do
    body = File.read!("docs/design/08_agent-server/alignment.md")
    refute body =~ ~r/lib\/jido\/agent_server\.ex:\d/
  end

  defp external_or_generated?(target) do
    target == "" or String.starts_with?(target, ["#", "http://", "https://", "mailto:"]) or
      String.ends_with?(target, ".html")
  end
end
