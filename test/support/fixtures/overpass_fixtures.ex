defmodule Dogo.OverpassFixtures do
  @moduledoc """
  Snimljeni Overpass odgovori. Testovi ih čitaju s diska umjesto da zovu mrežu.
  """

  @fixtures_path Path.join(__DIR__, "overpass")

  @doc "Sirovi JSON tekst snimljenog odgovora."
  def raw(name), do: File.read!(Path.join(@fixtures_path, "#{name}.json"))

  @doc "Dekodirani snimljeni odgovor."
  def decoded(name), do: name |> raw() |> Jason.decode!()
end
