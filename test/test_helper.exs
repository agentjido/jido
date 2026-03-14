# Suppress the Discovery module's info log during startup
# The capture_log: true option captures test logs, but Discovery logs happen
# before tests run. We handle this by temporarily setting compile_time_purge_level.
# However, since that's a compile-time option, we accept the Discovery log.

ExUnit.start()
ExUnit.configure(exclude: [:skip, :flaky, :example])
