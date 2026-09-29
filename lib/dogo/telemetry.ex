defmodule Dogo.Telemetry do
  @moduledoc """
  Telemetry eventovi domene (E7-S4).

  Dvije stvari koje vrijedi mjeriti, jer o njima ovisi korisnikov dojam, a
  ne vide se u metrikama Phoenixa i Ecta:

    * `[:dogo, :beaches, :query, :start | :stop | :exception]` — prostorni
      upiti, s metapodatkom `:query` (`:nearest`, `:within_bbox`,
      `:cluster_in_bbox`)
    * `[:dogo, :external, :request, :start | :stop | :exception]` — pozivi
      vanjskim servisima, s metapodacima `:service` (`:overpass`,
      `:nominatim`, `:osrm`) i, na `:stop`, `:result` (`:ok` ili `:error`)

  Metapodaci namjerno **ne sadrže argumente** — ni koordinate ni upite.
  Polazište upita često je korisnikova lokacija, a telemetry handleri
  (reporteri, logovi) su izvan dosega ovog modula.
  """

  @doc "Mjeri prostorni upit nad plažama."
  @spec spatial_query(atom(), (-> result)) :: result when result: term()
  def spatial_query(query, fun) when is_atom(query) do
    :telemetry.span([:dogo, :beaches, :query], %{query: query}, fn ->
      {fun.(), %{query: query}}
    end)
  end

  @doc "Mjeri poziv vanjskom servisu i bilježi je li uspio."
  @spec external_request(atom(), (-> result)) :: result when result: term()
  def external_request(service, fun) when is_atom(service) do
    :telemetry.span([:dogo, :external, :request], %{service: service}, fn ->
      result = fun.()
      {result, %{service: service, result: outcome(result)}}
    end)
  end

  defp outcome({:error, _reason}), do: :error
  defp outcome(_result), do: :ok
end
