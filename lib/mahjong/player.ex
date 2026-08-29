defmodule Mahjong.Player do
  @moduledoc """
  玩家状态与动作：摸牌、出牌、碰/吃/杠。副露以结构化 meld 表示：

      %{type: :pong | :chow | :kong_open | :kong_concealed | :kong_added,
        tiles: [tile], from: String.t() | nil}
  """

  defstruct [:id, :token, :position, :hand, :open_hand, :discards, :in_turn?, :game_id, :won?]

  alias Ecto.UUID
  alias Mahjong.Tile

  def new(attrs \\ %{}) do
    %__MODULE__{
      id: UUID.generate(),
      token: attrs[:token],
      position: attrs[:position],
      hand: attrs[:hand] || [],
      open_hand: [],
      discards: [],
      in_turn?: false,
      game_id: nil,
      won?: false
    }
  end

  @doc "手牌按花色（万/筒/条）与点数排序"
  def sort_hand(hand) do
    Enum.sort_by(hand, &{Tile.suit_rank(&1.suit), &1.value})
  end

  @doc "摸牌（牌追加到手牌末端，即听牌位）"
  def draw(player, tile) do
    %{player | hand: player.hand ++ [tile], in_turn?: true}
  end

  @doc "出牌"
  def discard(player, tile) do
    %{
      player
      | hand: Tile.remove_one(player.hand, tile),
        discards: player.discards ++ [tile],
        in_turn?: false
    }
  end

  @doc "碰：手牌中两张同牌 + 别人打出的牌组成刻子"
  def pong(player, tile, from_id) do
    meld = %{type: :pong, tiles: List.duplicate(tile, 3), from: from_id}

    hand =
      player.hand
      |> Tile.remove_one(tile)
      |> Tile.remove_one(tile)

    %{player | hand: hand, open_hand: [meld | player.open_hand]}
  end

  @doc "吃：base 为顺子最小点数，claimed 为别人打出的牌"
  def chow(player, claimed, base, from_id) do
    tiles = for v <- base..(base + 2), do: %{claimed | value: v}
    meld = %{type: :chow, tiles: tiles, from: from_id}

    hand =
      for v <- base..(base + 2), v != claimed.value, reduce: player.hand do
        acc -> Tile.remove_one(acc, %{claimed | value: v})
      end

    %{player | hand: hand, open_hand: [meld | player.open_hand]}
  end

  @doc "明杠：手牌三张同牌 + 别人打出的牌"
  def kong_open(player, tile, from_id) do
    meld = %{type: :kong_open, tiles: List.duplicate(tile, 4), from: from_id}

    hand =
      1..3
      |> Enum.reduce(player.hand, fn _, acc -> Tile.remove_one(acc, tile) end)

    %{player | hand: hand, open_hand: [meld | player.open_hand]}
  end

  @doc "暗杠：手牌四张同牌"
  def kong_concealed(player, tile) do
    meld = %{type: :kong_concealed, tiles: List.duplicate(tile, 4), from: nil}

    hand =
      1..4
      |> Enum.reduce(player.hand, fn _, acc -> Tile.remove_one(acc, tile) end)

    %{player | hand: hand, open_hand: [meld | player.open_hand]}
  end

  @doc "加杠：已有碰的副露补入第四张"
  def kong_added(player, tile) do
    open_hand =
      Enum.map(player.open_hand, fn meld ->
        if meld.type == :pong and Tile.same?(hd(meld.tiles), tile) do
          %{meld | type: :kong_added, tiles: meld.tiles ++ [tile]}
        else
          meld
        end
      end)

    %{player | hand: Tile.remove_one(player.hand, tile), open_hand: open_hand}
  end

  def win(player) do
    %{player | won?: true}
  end
end
