defmodule Examples.PhoenixIssueTriage.IssueTriage.Policy do
  @moduledoc """
  Example-specific workflow heuristics for the issue triage showcase.

  These rules are not Jido runtime concerns; they stand in for whatever
  classification or policy logic a real app would own.
  """

  @spec classify(String.t(), String.t(), [String.t()]) :: atom()
  def classify(title, body, labels) do
    downcased = Enum.map(labels, &String.downcase/1)
    haystack = String.downcase("#{title}\n#{body}")

    cond do
      "bug" in downcased or String.contains?(haystack, "crash") or
          String.contains?(haystack, "error") ->
        :bug

      "support" in downcased or String.contains?(haystack, "how do i") ->
        :support

      true ->
        :feature
    end
  end

  @spec priority(String.t(), [String.t()]) :: atom()
  def priority(body, labels) do
    downcased = Enum.map(labels, &String.downcase/1)
    haystack = String.downcase(body)

    cond do
      "urgent" in downcased or "p0" in downcased or String.contains?(haystack, "production") ->
        :high

      "needs-research" in downcased or String.contains?(haystack, "unknown root cause") ->
        :medium

      true ->
        :normal
    end
  end

  @spec requires_research?(String.t(), [String.t()]) :: boolean()
  def requires_research?(body, labels) do
    downcased = Enum.map(labels, &String.downcase/1)
    haystack = String.downcase(body)

    "needs-research" in downcased or
      String.contains?(haystack, "unknown root cause") or
      String.contains?(haystack, "deep dive")
  end

  @spec review_outcome(atom(), String.t()) :: atom()
  def review_outcome(priority, research_summary) do
    cond do
      priority == :high and research_summary in ["", nil] ->
        :changes_requested

      true ->
        :approved
    end
  end
end
