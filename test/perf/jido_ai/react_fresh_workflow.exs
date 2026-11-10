Code.require_file("react_support.exs", __DIR__)

options = Jido.Test.Perf.AI.ReActSupport.parse!(System.argv())
Jido.Test.Perf.AI.ReActSupport.report!(:fresh_workflow, options)
