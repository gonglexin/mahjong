defmodule Mahjong.Tile do
  @enforce_keys [:id, :suit, :value]
  defstruct [:id, :suit, :value]

  alias Ecto.UUID

  @type t :: %__MODULE__{
          id: UUID.t(),
          suit: atom(),
          value: integer()
        }

  @suits [:characters, :dots, :bamboos]

  def suits, do: @suits

  def new(attrs \\ %{}) do
    %__MODULE__{id: UUID.generate(), suit: attrs[:suit], value: attrs[:value]}
  end
end
