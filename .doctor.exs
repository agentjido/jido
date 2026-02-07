%Doctor.Config{
  ignore_modules: [
    # These modules use macros that generate code inside quote blocks.
    # Doctor incorrectly counts def statements inside quote as module functions.
    Jido.Agent,
    Jido.Plugin,
    Jido.Skill
  ],
  ignore_paths: [],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 100,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
