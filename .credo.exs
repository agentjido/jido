%{
  configs: [
    %{
      name: "default",
      plugins: [{ExSlop, []}],
      checks: [
        {Credo.Check.Design.AliasUsage, false},
        {ExSlop.Check.Readability.NarratorDoc, false}
      ]
    }
  ]
}
