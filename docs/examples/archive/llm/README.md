> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Archived LLM research profiles

The 20 earlier LLM profiles are replaced by 10 SDK integration fixtures. The
profiles retain domain requirements and source attribution. The earlier local
suite passed 64 tests and skipped one unfinished Deep Research case. The full
Deep Research plan/search/fetch/revise loop remains unimplemented; removal of
its skipped test does not mark that research feature complete.

Source and tests for the 19 original examples are available at commit
`357b22a`. RLM was local work and is retained in full as Recursive Analysis.
See the [current suite](../../../../test/examples/03_llm/README.md).

| Earlier profile | Current fixture |
| --- | --- |
| [03_01_agentic_rag](03_01_agentic_rag.md) | [Output Repair](../../profiles/03_llm/03_07_output_repair.md), [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_02_coding_assistant](03_02_coding_assistant.md) | [Tool Call](../../profiles/03_llm/03_03_tool_call.md) |
| [03_03_company_research](03_03_company_research.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_04_conversation_summarization](03_04_conversation_summarization.md) | [Context Compaction](../../profiles/03_llm/03_08_context_compaction.md) |
| [03_05_conversational_rag_memory](03_05_conversational_rag_memory.md) | [Conversation History](../../profiles/03_llm/03_02_conversation_history.md), [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_06_data_analyst](03_06_data_analyst.md) | [Tool Call](../../profiles/03_llm/03_03_tool_call.md) |
| [03_07_deep_research](03_07_deep_research.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_08_document_question_answering](03_08_document_question_answering.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_09_literature_review](03_09_literature_review.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_10_marketing_strategy](03_10_marketing_strategy.md) | [Output Repair](../../profiles/03_llm/03_07_output_repair.md), [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_11_model_fallback](03_11_model_fallback.md) | [Model Response](../../profiles/03_llm/03_01_model_response.md) |
| [03_12_multimodal_document_agent](03_12_multimodal_document_agent.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_13_plan_and_execute](03_13_plan_and_execute.md) | [Parallel Tools](../../profiles/03_llm/03_05_parallel_tools.md) |
| [03_14_rag_web_fallback](03_14_rag_web_fallback.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_15_react_agent](03_15_react_agent.md) | [Tool Loop](../../profiles/03_llm/03_04_tool_loop.md) |
| [03_16_self_evaluation_loop](03_16_self_evaluation_loop.md) | [Output Repair](../../profiles/03_llm/03_07_output_repair.md) |
| [03_17_single_tool_agent](03_17_single_tool_agent.md) | [Tool Call](../../profiles/03_llm/03_03_tool_call.md) |
| [03_18_starter_chatbot](03_18_starter_chatbot.md) | [Model Response](../../profiles/03_llm/03_01_model_response.md), [Conversation History](../../profiles/03_llm/03_02_conversation_history.md) |
| [03_19_stock_analysis](03_19_stock_analysis.md) | [Grounded Answer](../../profiles/03_llm/03_06_grounded_answer.md) |
| [03_20_recursive_language_model](03_20_recursive_language_model.md) | [Recursive Analysis](../../profiles/03_llm/03_10_recursive_analysis.md) |

Subagent Delegation is new. It starts real child Actors. The earlier ReAct and RLM tests are retained and extended where needed. The finite precomputed plan case lives with Parallel Tools at concurrency one, where complete plan admission is already tested.
