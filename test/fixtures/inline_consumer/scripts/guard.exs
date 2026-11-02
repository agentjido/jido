# Port closure also closes stdin. Stop the VM if the ExUnit owner exits.
spawn(fn ->
  IO.binread(:stdio, :eof)
  System.halt(125)
end)

# This limit also applies if the test VM stops before it can close the port.
spawn(fn ->
  receive do
  after
    # The parent reports and kills a timed-out child after 40 seconds. This
    # fallback must run later, so it cannot hide the parent's diagnostic.
    45_000 -> System.halt(124)
  end
end)
