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

  def same?(%__MODULE__{} = a, %__MODULE__{} = b), do: a.suit == b.suit and a.value == b.value

  def key(%__MODULE__{} = tile), do: {tile.suit, tile.value}

  # 只移除第一张匹配花色+点数的牌（手牌可能有两张相同牌，只应消失一张）
  def remove_one(hand, %__MODULE__{} = tile) do
    case Enum.find_index(hand, &same?(&1, tile)) do
      nil -> hand
      index -> List.delete_at(hand, index)
    end
  end

  def count(hand, %__MODULE__{} = tile) do
    Enum.count(hand, &same?(&1, tile))
  end

  def suit_rank(:characters), do: 0
  def suit_rank(:dots), do: 1
  def suit_rank(:bamboos), do: 2

  def suits, do: @suits

  def new(attrs \\ %{}) do
    %__MODULE__{id: UUID.generate(), suit: attrs[:suit], value: attrs[:value]}
  end
end
