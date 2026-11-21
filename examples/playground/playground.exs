Code.require_file("../support/offline_inference_client.ex", __DIR__)
Code.require_file("../24_application_patterns/24_09_support_desk/reasoning.ex", __DIR__)
Code.require_file("../24_application_patterns/24_09_support_desk/support_desk.ex", __DIR__)
Code.require_file("../24_application_patterns/24_09_support_desk/scripted_client.ex", __DIR__)
Code.require_file("../00_start_here/00_05_hosted_agent/hosted_agent.ex", __DIR__)
Code.require_file("preview.ex", __DIR__)
Code.require_file("test_runner.ex", __DIR__)
Code.require_file("explorer_live.ex", __DIR__)

PhoenixPlayground.start(
  live: Jido.Examples.ExplorerLive,
  child_specs: [{Jido, name: Jido.Examples.ExplorerRuntime}],
  port: 4011,
  open_browser: false,
  live_reload: false
)
