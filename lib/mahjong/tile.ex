defmodule Mahjong.Tile do
  @enforce_keys [:suit, :value]
  defstruct [:suit, :value]

  @type t :: %__MODULE__{
          suit: atom(),
          value: integer()
        }

  @suits [:characters, :dots, :bamboos]

  def suits, do: @suits

  def new(suit, value) do
    %__MODULE__{suit: suit, value: value}
  end
end
