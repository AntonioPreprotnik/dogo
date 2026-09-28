defmodule DogoWeb.BeachFilters do
  @moduledoc """
  Stanje filtera, čitano iz query stringa i natrag u njega.

  Cijelo stanje pretrage živi u URL-u, pa je svaki prikaz djeljiv linkom i
  preživi osvježavanje stranice.

  Vrijednosti iz URL-a nikad ne pretvaramo u atome dinamički — dopušteni skup
  je zaključan popisima iz sheme, a sve ostalo se tiho odbacuje. Neispravan
  link tako daje prazan filter umjesto greške.
  """

  alias Dogo.Beaches
  alias Dogo.Beaches.Beach

  @type t :: %__MODULE__{
          dog_status: [atom()],
          surface: [atom()],
          amenities: [atom()],
          radius_m: pos_integer() | nil
        }

  defstruct dog_status: [], surface: [], amenities: [], radius_m: nil

  @amenity_filters ~w(dog_shower shade water)a

  @doc "Sadržaji koje sučelje nudi kao filter."
  def amenity_filters, do: @amenity_filters

  @doc """
  Filteri iz parametara rute.

      iex> DogoWeb.BeachFilters.parse(%{"dog" => "designated,allowed"})
      %DogoWeb.BeachFilters{dog_status: [:designated, :allowed]}
  """
  @spec parse(map()) :: t()
  def parse(params) do
    %__MODULE__{
      dog_status: parse_list(params["dog"], Beach.dog_statuses()),
      surface: parse_list(params["surface"], Beach.surfaces()),
      amenities: parse_list(params["amenities"], @amenity_filters),
      radius_m: parse_radius(params["radius"])
    }
  end

  @doc """
  Parametri za URL. Prazni filteri se izostavljaju, da link ostane kratak i
  da se isto stanje uvijek zapiše na isti način.
  """
  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = filters) do
    %{}
    |> put_list("dog", filters.dog_status)
    |> put_list("surface", filters.surface)
    |> put_list("amenities", filters.amenities)
    |> put_radius(filters.radius_m)
  end

  @doc "Opcije za `Dogo.Beaches` upite."
  @spec to_opts(t()) :: keyword()
  def to_opts(%__MODULE__{} = filters) do
    [
      dog_status: filters.dog_status,
      surface: filters.surface,
      amenities: filters.amenities,
      within_m: filters.radius_m
    ]
  end

  @doc "Je li ijedan filter aktivan?"
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{} = filters) do
    filters.dog_status != [] or filters.surface != [] or filters.amenities != [] or
      filters.radius_m != nil
  end

  @doc "Filteri iz podataka forme (checkboxi šalju mapu ključ => \"true\")."
  @spec from_form(map()) :: t()
  def from_form(params) do
    %__MODULE__{
      dog_status: checked(params["dog"], Beach.dog_statuses()),
      surface: checked(params["surface"], Beach.surfaces()),
      amenities: checked(params["amenities"], @amenity_filters),
      radius_m: parse_radius(params["radius"])
    }
  end

  @doc "Prazni filteri."
  @spec clear() :: t()
  def clear, do: %__MODULE__{}

  defp parse_list(nil, _allowed), do: []

  defp parse_list(value, allowed) when is_binary(value) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(&List.wrap(allowed_by_name[&1]))
    |> Enum.uniq()
  end

  defp parse_list(_value, _allowed), do: []

  defp parse_radius(value) when is_binary(value) do
    case Integer.parse(value) do
      {radius, ""} -> if radius in Beaches.radii_m(), do: radius
      _ -> nil
    end
  end

  defp parse_radius(_), do: nil

  defp checked(nil, _allowed), do: []

  defp checked(values, allowed) when is_map(values) do
    allowed_by_name = Map.new(allowed, &{to_string(&1), &1})

    for {key, "true"} <- values, value = allowed_by_name[key], do: value
  end

  defp checked(_values, _allowed), do: []

  defp put_list(params, _key, []), do: params

  defp put_list(params, key, values) do
    Map.put(params, key, values |> Enum.sort() |> Enum.map_join(",", &to_string/1))
  end

  defp put_radius(params, nil), do: params
  defp put_radius(params, radius), do: Map.put(params, "radius", to_string(radius))
end
