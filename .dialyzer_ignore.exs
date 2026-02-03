[
  # Mix task modules use Mix functions that are not in dialyzer's PLT
  # These are expected false positives
  {"lib/mix/tasks/jido.gen.agent.ex", :unknown_function},
  {"lib/mix/tasks/jido.gen.agent.ex", :callback_info_missing},
  {"lib/mix/tasks/jido.gen.sensor.ex", :unknown_function},
  {"lib/mix/tasks/jido.gen.sensor.ex", :callback_info_missing},
  {"lib/mix/tasks/jido.gen.plugin.ex", :unknown_function},
  {"lib/mix/tasks/jido.gen.plugin.ex", :callback_info_missing},
  {"lib/mix/tasks/jido.install.ex", :unknown_function},
  {"lib/mix/tasks/jido.install.ex", :callback_info_missing}
]
