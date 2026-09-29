defmodule DogoWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("dogo.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("dogo.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("dogo.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("dogo.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("dogo.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # Domena (E7-S4). Metapodaci su samo nazivi upita i servisa, nikad
      # koordinate — vidi Dogo.Telemetry.
      summary("dogo.beaches.query.stop.duration",
        tags: [:query],
        unit: {:native, :millisecond},
        description: "Trajanje prostornog upita nad plažama"
      ),
      summary("dogo.external.request.stop.duration",
        tags: [:service, :result],
        unit: {:native, :millisecond},
        description: "Trajanje poziva vanjskom servisu"
      ),
      counter("dogo.external.request.stop.duration",
        tags: [:service, :result],
        description: "Broj poziva vanjskim servisima, po ishodu"
      ),
      counter("dogo.external.request.exception.duration",
        tags: [:service],
        description: "Pozivi vanjskim servisima koji su završili iznimkom"
      ),

      # Uvoz
      summary("oban.job.stop.duration",
        tags: [:worker, :state],
        tag_values: &oban_tags/1,
        unit: {:native, :millisecond},
        description: "Trajanje Oban jobova (uvoz plaža i otoka)"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp oban_tags(%{job: job, state: state}), do: %{worker: job.worker, state: state}
  defp oban_tags(metadata), do: metadata

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {DogoWeb, :count_users, []}
    ]
  end
end
