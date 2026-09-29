defmodule DogoWeb.OfflineSnapshot do
  @moduledoc """
  Sažetak liste rezultata koji preglednik sprema za rad bez mreže (E6-S3).

  Kad LiveView socket nije dostupan, server ne može ništa renderirati, pa
  preglednik prikazuje zadnji spremljeni sažetak. Zato sažetak nosi **gotove,
  prevedene tekstove**: klijent ih samo ispisuje i ne treba znati ni jezik
  ni pravila formatiranja.

  Namjerno ne sadrži polazište. Korisnikova lokacija se ne sprema (vidi
  `CLAUDE.md`), pa ni u preglednikovu IndexedDB ne ide ništa osim samih
  plaža.
  """
  use Gettext, backend: DogoWeb.Gettext

  import DogoWeb.BeachComponents,
    only: [
      dog_status_label: 1,
      surface_label: 1,
      format_distance: 1,
      format_duration: 1,
      google_maps_url: 2,
      marker_colors: 0
    ]

  @doc """
  Sažetak za već poredanu listu plaža, s vremenom vožnje gdje je poznato.
  """
  @spec build([Dogo.Beaches.Beach.t()], %{optional(term()) => map() | nil}) :: map()
  def build(beaches, driving) do
    %{
      labels: labels(),
      beaches: Enum.map(beaches, &beach(&1, driving[&1.id]))
    }
  end

  defp labels do
    %{
      offline: gettext("Offline"),
      # Vrijeme popunjava preglednik, u lokalnom vremenu korisnika, pa se
      # placeholder prosljeduje dalje netaknut.
      saved_at:
        gettext("No connection. These are the last results, saved at %{time}.",
          time: "%{time}"
        ),
      navigate: gettext("Navigate")
    }
  end

  defp beach(beach, leg) do
    %Geo.Point{coordinates: {lon, lat}} = beach.geom

    %{
      id: beach.id,
      name: beach.name || gettext("Unnamed beach"),
      details: "#{dog_status_label(beach.dog_status)} · #{surface_label(beach.surface)}",
      distance: distance(beach.distance_m, leg),
      color: Map.fetch!(marker_colors(), beach.dog_status),
      navigate_url: google_maps_url(lat, lon)
    }
  end

  defp distance(nil, nil), do: nil
  defp distance(metres, nil), do: "≈ " <> format_distance(metres)

  defp distance(metres, %{duration_s: seconds}) do
    [format_duration(seconds), format_distance(metres)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end
end
