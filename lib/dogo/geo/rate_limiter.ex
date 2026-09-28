defmodule Dogo.Geo.RateLimiter do
  @moduledoc """
  Propušta najviše jedan zahtjev u zadanom intervalu, kroz cijeli čvor.

  Nominatimova usage policy traži najviše 1 zahtjev u sekundi. Ograničenje mora
  biti globalno, ne po procesu, jer svaki posjetitelj ima svoj LiveView proces.

  GenServer **ne obavlja** sam HTTP poziv, nego samo kaže koliko treba pričekati.
  Da poziv radi u njemu, jedan spor odgovor blokirao bi sve ostale.
  """
  use GenServer

  @default_interval_ms 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc """
  Čeka dok red ne dođe na pozivatelja.

  Vraća `:ok`, ili `{:error, :timeout}` ako bi čekanje bilo dulje od `:timeout`
  (zadano 3 s) — bolje odustati nego držati korisnika u neizvjesnosti.
  """
  @spec acquire(keyword()) :: :ok | {:error, :timeout}
  def acquire(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    max_wait = Keyword.get(opts, :timeout, 3_000)

    case GenServer.call(server, :acquire, max_wait + 1_000) do
      {:wait, ms} when ms > max_wait ->
        {:error, :timeout}

      {:wait, 0} ->
        :ok

      {:wait, ms} ->
        Process.sleep(ms)
        :ok
    end
  end

  @impl GenServer
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)

    {:ok, %{interval_ms: interval, next_allowed_at: monotonic_ms()}}
  end

  @impl GenServer
  def handle_call(:acquire, _from, state) do
    now = monotonic_ms()
    slot = max(state.next_allowed_at, now)

    {:reply, {:wait, slot - now}, %{state | next_allowed_at: slot + state.interval_ms}}
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
