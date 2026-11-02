defmodule Jido.Authoring.IssueTest do
  use ExUnit.Case, async: true

  alias Jido.Authoring.Issue

  test "normalizes unsafe details and accepts JSON path indexes" do
    issue = Issue.new(:invalid_value, ["items", 0], "invalid value", details: %{pid: self()})

    assert Issue.valid?(issue)
    assert %{value: inspected} = issue.details
    assert inspected =~ "pid:"

    issue = Issue.new(:invalid_value, [], "invalid value", details: self())

    assert Issue.valid?(issue)
    assert %{value: inspected} = issue.details
    assert inspected =~ "#PID<"
  end

  test "rejects malformed issue values and paths" do
    refute Issue.valid?(:not_an_issue)

    for issue <- [
          %Issue{code: nil, path: [], message: "invalid"},
          %Issue{code: :invalid, path: :not_a_path, message: "invalid"},
          %Issue{code: :invalid, path: ["items", -1], message: "invalid"},
          %Issue{code: :invalid, path: ["items", :invalid], message: "invalid"},
          %Issue{code: :invalid, path: ["items" | :invalid], message: "invalid"}
        ] do
      refute Issue.valid?(issue)
    end
  end
end
