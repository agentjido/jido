defmodule Jido.AI.Browser.Address do
  @moduledoc false

  # Special-purpose ranges adapted from Jido Browser's DestinationPolicy (Apache-2.0).
  import Bitwise, only: [bsl: 2, bsr: 2]

  # IANA IPv4 Special-Purpose Address Space plus the IPv4 multicast block.
  # https://www.iana.org/assignments/iana-ipv4-special-registry/
  @ipv4_special_ranges [
    {{0, 0, 0, 0}, 8, :this_network},
    {{10, 0, 0, 0}, 8, :private},
    {{100, 64, 0, 0}, 10, :shared_address_space},
    {{127, 0, 0, 0}, 8, :loopback},
    {{169, 254, 0, 0}, 16, :link_local},
    {{172, 16, 0, 0}, 12, :private},
    {{192, 0, 0, 0}, 24, :special_use},
    {{192, 0, 2, 0}, 24, :documentation},
    {{192, 31, 196, 0}, 24, :special_use},
    {{192, 52, 193, 0}, 24, :special_use},
    {{192, 88, 99, 0}, 24, :special_use},
    {{192, 168, 0, 0}, 16, :private},
    {{192, 175, 48, 0}, 24, :special_use},
    {{198, 18, 0, 0}, 15, :benchmarking},
    {{198, 51, 100, 0}, 24, :documentation},
    {{203, 0, 113, 0}, 24, :documentation},
    {{224, 0, 0, 0}, 4, :multicast},
    {{240, 0, 0, 0}, 4, :reserved}
  ]
  # IANA IPv6 Special-Purpose Address Space. All other allowed IPv6 addresses
  # must also be in the global-unicast 2000::/3 block.
  # https://www.iana.org/assignments/iana-ipv6-special-registry/
  @ipv6_special_ranges [
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128, :unspecified},
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128, :loopback},
    {{0, 0, 0, 0, 0, 0xFFFF, 0, 0}, 96, :ipv4_mapped},
    {{0x0064, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96, :translation},
    {{0x0064, 0xFF9B, 1, 0, 0, 0, 0, 0}, 48, :translation},
    {{0x0100, 0, 0, 0, 0, 0, 0, 0}, 64, :discard_only},
    {{0x0100, 0, 0, 1, 0, 0, 0, 0}, 64, :special_use},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23, :special_use},
    {{0x2001, 0x0DB8, 0, 0, 0, 0, 0, 0}, 32, :documentation},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16, :special_use},
    {{0x2620, 0x004F, 0x8000, 0, 0, 0, 0, 0}, 48, :special_use},
    {{0x3FFF, 0, 0, 0, 0, 0, 0, 0}, 20, :documentation},
    {{0x5F00, 0, 0, 0, 0, 0, 0, 0}, 16, :special_use},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7, :private},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10, :link_local},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8, :multicast}
  ]
  @ipv6_global_unicast {{0x2000, 0, 0, 0, 0, 0, 0, 0}, 3}

  def resolve(host) do
    addresses =
      for family <- [:inet, :inet6],
          {:ok, addresses} <- [:inet.getaddrs(String.to_charlist(host), family)],
          address <- addresses,
          do: address

    case addresses do
      [address | _] ->
        if Enum.all?(addresses, &public?/1), do: {:ok, address}, else: {:error, :destination_blocked}

      [] ->
        {:error, :dns_failed}
    end
  end

  def public?(address), do: is_nil(blocked_address_reason(address))

  defp blocked_address_reason({_a, _b, _c, _d} = address) do
    range_reason(address, @ipv4_special_ranges)
  end

  defp blocked_address_reason({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    case range_reason(address, @ipv6_special_ranges) do
      nil -> if address_in_range?(address, @ipv6_global_unicast), do: nil, else: :non_global
      reason -> reason
    end
  end

  defp range_reason(address, ranges) do
    Enum.find_value(ranges, fn {prefix, prefix_length, reason} ->
      if address_in_range?(address, {prefix, prefix_length}), do: reason
    end)
  end

  defp address_in_range?(address, {prefix, prefix_length}) do
    {address_value, bit_count} = address_integer(address)
    {prefix_value, ^bit_count} = address_integer(prefix)
    shift = bit_count - prefix_length
    bsr(address_value, shift) == bsr(prefix_value, shift)
  end

  defp address_integer({_a, _b, _c, _d} = address) do
    {join_address_parts(Tuple.to_list(address), 8), 32}
  end

  defp address_integer({_a, _b, _c, _d, _e, _f, _g, _h} = address) do
    {join_address_parts(Tuple.to_list(address), 16), 128}
  end

  defp join_address_parts(parts, part_bits) do
    Enum.reduce(parts, 0, fn part, value -> bsl(value, part_bits) + part end)
  end
end
