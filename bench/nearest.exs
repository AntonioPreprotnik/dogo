# Mjeri koliko prostorni indeks vrijedi za osnovni upit aplikacije.
#
#     mix run bench/nearest.exs
#
# "Bez indeksa" se dobiva s `enable_indexscan`/`enable_bitmapscan = off` na
# razini transakcije. Isti upit, isti podaci, samo drugi plan — a indeks ne
# treba stvarno brisati, pa je mjerenje ponovljivo i bezopasno.

# Ecto debug log bi zatrpao mjerenje.
Logger.configure(level: :warning)

alias Dogo.Beaches
alias Dogo.Repo

point = %Geo.Point{coordinates: {16.4392, 43.5081}, srid: 4326}

count = Beaches.count_beaches()

if count < 100 do
  raise """
  U bazi je samo #{count} plaza. Napuni je prije mjerenja:

      mix beaches.import
  """
end

IO.puts("Plaza u bazi: #{count}\n")

without_index = fn fun ->
  Repo.transaction(fn ->
    Repo.query!("SET LOCAL enable_indexscan = off")
    Repo.query!("SET LOCAL enable_bitmapscan = off")
    fun.()
  end)
end

explain = fn label, fun ->
  {:ok, rows} =
    Repo.transaction(fn ->
      if label == :without_index do
        Repo.query!("SET LOCAL enable_indexscan = off")
        Repo.query!("SET LOCAL enable_bitmapscan = off")
      end

      fun.()
    end)

  rows
end

knn_sql = """
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, ST_Distance(geom::geography, $1::geography) AS distance_m
FROM beaches
ORDER BY $1::geography <-> geom::geography
LIMIT 20
"""

for label <- [:with_index, :without_index] do
  %{rows: rows} = explain.(label, fn -> Repo.query!(knn_sql, [point]) end)

  IO.puts("== EXPLAIN ANALYZE (#{label}) ==")
  Enum.each(rows, fn [line] -> IO.puts(line) end)
  IO.puts("")
end

Benchee.run(
  %{
    "nearest/2 s indeksom" => fn -> Beaches.nearest(point, limit: 20) end,
    "nearest/2 bez indeksa" => fn -> without_index.(fn -> Beaches.nearest(point, limit: 20) end) end
  },
  time: 5,
  warmup: 2,
  memory_time: 0,
  print: [fast_warning: false]
)
