defmodule Dogo.Geo.Place do
  @moduledoc """
  Mjesto pronađeno geokodiranjem: ono malo što sučelju treba da ponudi izbor.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          point: Geo.Point.t()
        }

  @enforce_keys [:name, :point]
  defstruct [:name, :description, :point]
end
