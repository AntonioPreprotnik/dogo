defmodule DogoWeb.AdminLive.Imports do
  @moduledoc """
  Ponovno pokretanje uvoza iz sučelja i pregled zadnjih uvoznih jobova.

  Gumbi samo stavljaju job u Oban red, isto kao `mix beaches.import`. Jobovi
  su `unique`, pa dvostruki klik ne pokreće dva uvoza: Oban vrati postojeći
  job s oznakom `conflict?`.

  Dok neki job čeka ili radi, stranica se osvježava svakih nekoliko sekundi.
  """
  use DogoWeb, :live_view

  alias Dogo.Import

  @refresh_ms 3_000
  @active_states ~w(available scheduled executing retryable)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        {gettext("Imports")}
        <:subtitle>
          {gettext("Imports are idempotent. Beaches edited by hand are left unchanged.")}
        </:subtitle>
      </.header>

      <div class="grid gap-4 sm:grid-cols-2">
        <div class="rounded-xl border border-base-300 p-4">
          <h2 class="font-medium">{gettext("Beaches")}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("Fetches beaches from OpenStreetMap (Overpass).")}
          </p>
          <.button
            id="import-beaches"
            phx-click="import"
            phx-value-kind="beaches"
            phx-disable-with="…"
            class="btn btn-primary btn-sm mt-3"
          >
            {gettext("Run import")}
          </.button>
        </div>
        <div class="rounded-xl border border-base-300 p-4">
          <h2 class="font-medium">{gettext("Islands")}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("Fetches island polygons and assigns beaches to islands. Takes longer.")}
          </p>
          <.button
            id="import-islands"
            phx-click="import"
            phx-value-kind="islands"
            phx-disable-with="…"
            class="btn btn-primary btn-sm mt-3"
          >
            {gettext("Run import")}
          </.button>
        </div>
      </div>

      <section>
        <h2 class="mb-2 font-medium">{gettext("Recent jobs")}</h2>
        <p :if={@jobs == []} id="no-jobs" class="text-sm text-base-content/70">
          {gettext("No imports yet.")}
        </p>
        <div :if={@jobs != []} class="overflow-x-auto">
          <.table id="jobs" rows={@jobs} row_id={&"job-#{&1.id}"}>
            <:col :let={job} label="#">{job.id}</:col>
            <:col :let={job} label={gettext("Import")}>{job_kind(job)}</:col>
            <:col :let={job} label={gettext("State")}>
              <span
                data-role="job-state"
                data-state={job.state}
                class={["badge badge-sm", state_class(job.state)]}
              >
                {state_label(job.state)}
              </span>
            </:col>
            <:col :let={job} label={gettext("Queued")}>{format_time(job.inserted_at)}</:col>
            <:col :let={job} label={gettext("Finished")}>
              {format_time(job.completed_at || job.discarded_at || job.cancelled_at)}
            </:col>
            <:col :let={job} label={gettext("Attempts")}>{job.attempt}/{job.max_attempts}</:col>
          </.table>
        </div>
      </section>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Imports"))
     |> assign(:refresh_scheduled?, false)
     |> load_jobs()}
  end

  @impl true
  def handle_event("import", %{"kind" => kind}, socket) do
    socket =
      case enqueue(kind) do
        {:ok, %{conflict?: true}} ->
          put_flash(socket, :info, gettext("This import is already queued or running."))

        {:ok, _job} ->
          put_flash(socket, :info, gettext("Import queued."))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("The import could not be queued."))
      end

    {:noreply, load_jobs(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, socket |> assign(:refresh_scheduled?, false) |> load_jobs()}
  end

  defp enqueue("beaches"), do: Import.enqueue_beaches_import()
  defp enqueue("islands"), do: Import.enqueue_islands_import()

  defp load_jobs(socket) do
    jobs = Import.recent_jobs(10)

    socket
    |> assign(:jobs, jobs)
    |> maybe_schedule_refresh(Enum.any?(jobs, &(&1.state in @active_states)))
  end

  # Najviše jedan zakazani refresh, inače bi svaki klik dodao novi ciklus.
  defp maybe_schedule_refresh(socket, true) do
    if connected?(socket) and not socket.assigns.refresh_scheduled? do
      Process.send_after(self(), :refresh, @refresh_ms)
      assign(socket, :refresh_scheduled?, true)
    else
      socket
    end
  end

  defp maybe_schedule_refresh(socket, false), do: socket

  defp job_kind(%{worker: "Dogo.Import.Jobs.ImportBeaches"}), do: gettext("Beaches")
  defp job_kind(%{worker: "Dogo.Import.Jobs.ImportIslands"}), do: gettext("Islands")
  defp job_kind(%{worker: worker}), do: worker

  defp state_label("available"), do: gettext("waiting")
  defp state_label("scheduled"), do: gettext("scheduled")
  defp state_label("executing"), do: gettext("running")
  defp state_label("retryable"), do: gettext("will retry")
  defp state_label("completed"), do: gettext("completed")
  defp state_label("discarded"), do: gettext("failed")
  defp state_label("cancelled"), do: gettext("cancelled")
  defp state_label(state), do: state

  defp state_class("completed"), do: "badge-success"
  defp state_class(state) when state in ["discarded", "cancelled"], do: "badge-error"
  defp state_class("retryable"), do: "badge-warning"
  defp state_class(_state), do: "badge-info"

  defp format_time(nil), do: "—"
  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
