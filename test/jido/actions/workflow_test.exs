# defmodule Jido.Actions.WorkflowTest do
#   use JidoTest.Case, async: true

#   # Define a simple LogAction for testing
#   defmodule LogAction do
#     use Jido.Action,
#       name: "log_action",
#       description: "Logs a message",
#       schema: [
#         message: [type: :string, required: true]
#       ]

#     @impl true
#     def run(params, _context) do
#       # In a real implementation, this would log the message
#       {:ok, %{logged: params.message}}
#     end
#   end

#   # Define a condition action for testing
#   defmodule ConditionAction do
#     use Jido.Action,
#       name: "condition_action",
#       description: "Evaluates a condition",
#       schema: [
#         condition: [type: :boolean, required: true]
#       ]

#     @impl true
#     def run(params, _context) do
#       # Simply return the condition value
#       {:ok, %{result: params.condition}}
#     end
#   end

#   # Define test modules at the top level
#   defmodule ValidWorkflow do
#     use Jido.Actions.Workflow,
#       name: "valid_workflow",
#       description: "A valid test workflow",
#       schema: [
#         input: [type: :string, required: true]
#       ],
#       steps: [
#         {:step, [name: "log_step"], [{LogAction, message: "Processing input"}]},
#         {:step, [name: "uppercase_step"],
#          [
#            {LogAction, message: "Converting to uppercase"}
#          ]}
#       ]
#   end

#   defmodule ConditionalWorkflow do
#     use Jido.Actions.Workflow,
#       name: "conditional_workflow",
#       description: "A workflow with conditional steps",
#       schema: [
#         input: [type: :string, required: true],
#         condition: [type: :boolean, required: true]
#       ],
#       steps: [
#         {:step, [name: "initial_step"], [{LogAction, message: "Starting workflow"}]},
#         {:branch, [name: "condition_check"],
#          [
#            # Use a boolean value directly from params instead of an anonymous function
#            # This will be replaced at runtime with params.condition
#            true,
#            {:step, [name: "true_branch"], [{LogAction, message: "Condition was true"}]},
#            {:step, [name: "false_branch"], [{LogAction, message: "Condition was false"}]}
#          ]},
#         {:step, [name: "final_step"], [{LogAction, message: "Finishing workflow"}]}
#       ]

#     # Override execute_step to handle our specific condition check
#     @impl Jido.Actions.Workflow
#     def execute_step(
#           {:branch, [name: "condition_check"], [_placeholder, true_branch, false_branch]},
#           params,
#           context
#         ) do
#       # Use the condition from params
#       condition_value = params.condition

#       # Choose the branch based on the condition value
#       if condition_value do
#         execute_step(true_branch, params, context)
#       else
#         execute_step(false_branch, params, context)
#       end
#     end

#     # Fall back to the default implementation for other steps
#     def execute_step(step, params, context) do
#       super(step, params, context)
#     end
#   end

#   defmodule ParallelWorkflow do
#     use Jido.Actions.Workflow,
#       name: "parallel_workflow",
#       description: "A workflow with parallel steps",
#       schema: [
#         input: [type: :string, required: true]
#       ],
#       steps: [
#         {:step, [name: "initial_step"], [{LogAction, message: "Starting parallel workflow"}]},
#         {:parallel, [name: "parallel_steps"],
#          [
#            {:step, [name: "parallel_1"], [{LogAction, message: "Parallel step 1"}]},
#            {:step, [name: "parallel_2"], [{LogAction, message: "Parallel step 2"}]},
#            {:step, [name: "parallel_3"], [{LogAction, message: "Parallel step 3"}]}
#          ]},
#         {:step, [name: "final_step"], [{LogAction, message: "Finished parallel workflow"}]}
#       ]
#   end

#   describe "WorkflowAction module definition" do
#     test "creates a workflow action with valid options" do
#       assert ValidWorkflow.name() == "valid_workflow"
#       assert ValidWorkflow.description() == "A valid test workflow"
#     end

#     test "validates parameters using schema" do
#       params = %{}
#       _context = %{}

#       assert {:error, error} = ValidWorkflow.validate_params(params)
#       assert error.type == :validation_error
#     end
#   end

#   describe "WorkflowAction execution" do
#     test "executes a simple workflow" do
#       params = %{input: "test input"}
#       context = %{}

#       assert {:ok, result} = ValidWorkflow.run(params, context)
#       assert result.logged == "Converting to uppercase"
#     end

#     test "executes a conditional workflow with true condition" do
#       params = %{input: "test input", condition: true}
#       context = %{}

#       assert {:ok, result} = ConditionalWorkflow.run(params, context)
#       assert result.logged == "Finishing workflow"
#     end

#     test "executes a conditional workflow with false condition" do
#       params = %{input: "test input", condition: false}
#       context = %{}

#       assert {:ok, result} = ConditionalWorkflow.run(params, context)
#       assert result.logged == "Finishing workflow"
#     end

#     test "executes a workflow with parallel steps" do
#       params = %{input: "test input"}
#       context = %{}

#       assert {:ok, result} = ParallelWorkflow.run(params, context)
#       assert result.logged == "Finished parallel workflow"
#       assert Map.has_key?(result, :parallel_results)
#     end
#   end

#   describe "WorkflowAction integration" do
#     test "supports tool conversion like regular actions" do
#       tool = ValidWorkflow.to_tool()

#       # Check that we get a tool structure back
#       assert is_map(tool)
#       assert Map.has_key?(tool, "name")
#       assert Map.has_key?(tool, "description")
#       assert Map.has_key?(tool, "parameters")

#       # Validate tool contents
#       assert tool["name"] == "valid_workflow"
#       assert tool["description"] == "A valid test workflow"
#     end
#   end
# end
