defmodule Dogo.Geo.RateLimiterTest do
  @moduledoc "E4-S2: Nominatim dopušta najviše jedan zahtjev u sekundi."
  use ExUnit.Case, async: true

  alias Dogo.Geo.RateLimiter

  defp start_limiter(interval_ms) do
    name = :"limiter_#{System.unique_integer([:positive])}"
    start_supervised!({RateLimiter, name: name, interval_ms: interval_ms})
    name
  end

  test "prvi poziv prolazi odmah" do
    server = start_limiter(1_000)

    {elapsed, :ok} = :timer.tc(fn -> RateLimiter.acquire(server: server) end, :millisecond)

    assert elapsed < 50
  end

  test "drugi poziv čeka interval" do
    server = start_limiter(200)

    :ok = RateLimiter.acquire(server: server)
    {elapsed, :ok} = :timer.tc(fn -> RateLimiter.acquire(server: server) end, :millisecond)

    assert elapsed >= 190
  end

  test "termini se dijele redom, ne svi u isti tren" do
    server = start_limiter(100)

    {elapsed, _} =
      :timer.tc(
        fn ->
          1..4
          |> Task.async_stream(fn _ -> RateLimiter.acquire(server: server) end,
            max_concurrency: 4
          )
          |> Enum.to_list()
        end,
        :millisecond
      )

    # Cetiri poziva uz razmak od 100 ms: zadnji ceka barem 300 ms.
    assert elapsed >= 290
  end

  test "odustaje kad bi čekanje bilo predugo" do
    server = start_limiter(5_000)

    :ok = RateLimiter.acquire(server: server)

    assert {:error, :timeout} = RateLimiter.acquire(server: server, timeout: 100)
  end

  test "ograničenje je globalno, ne po procesu" do
    server = start_limiter(200)

    :ok = RateLimiter.acquire(server: server)

    task =
      Task.async(fn -> :timer.tc(fn -> RateLimiter.acquire(server: server) end, :millisecond) end)

    {elapsed, :ok} = Task.await(task)

    assert elapsed >= 190
  end
end
