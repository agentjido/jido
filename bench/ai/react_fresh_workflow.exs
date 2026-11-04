Code.require_file("react_support.exs", __DIR__)

options = Jido.Bench.AI.ReActSupport.parse!(System.argv())
Jido.Bench.AI.ReActSupport.report!(:fresh_workflow, options)
