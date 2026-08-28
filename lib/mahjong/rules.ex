defmodule Mahjong.Rules do
  @moduledoc """
  长沙麻将规则：108 张（万/筒/条），胡牌判定与番型。

  - 平胡：四副牌（顺子/刻子）+ 一对将，将必须为 2/5/8
  - 碰碰胡：全部为刻子（含杠）+ 一对将，任意将
  - 七对：门清七个对子，任意将
  - 清一色：手牌与副露全部为同一门花色
  - 附加番：自摸 / 天胡 / 地胡 / 杠上开花
  """

  alias Mahjong.Tile

  @type meld_type :: :pong | :chow | :kong_open | :kong_concealed | :kong_added

  @type meld :: %{type: meld_type(), tiles: [Tile.t()], from: String.t() | nil}

  @type flag :: :self_draw | :heavenly | :earthly | :kong_blossom

  @fan_names %{
    ping_hu: "平胡",
    pung_pung: "碰碰胡",
    seven_pairs: "七对",
    pure_suit: "清一色",
    self_draw: "自摸",
    heavenly: "天胡",
    earthly: "地胡",
    kong_blossom: "杠上开花"
  }

  @type fan :: :ping_hu | :pung_pung | :seven_pairs | :pure_suit | flag()

  @spec fan_name(fan()) :: String.t()
  def fan_name(fan), do: Map.fetch!(@fan_names, fan)

  @doc """
  判定 14 张牌（手牌 + 副露）是否胡牌。

  返回 `{:win, fans, score}`，番数 = 番型数量；不胡返回 `:no_win`。
  """
  @spec check([Tile.t()], [meld()], [flag()]) :: {:win, [fan()], pos_integer()} | :no_win
  def check(hand, melds \\ [], flags \\ []) do
    base_fans =
      cond do
        seven_pairs?(hand, melds) -> [:seven_pairs]
        win = standard_win(hand, melds) -> win
        true -> nil
      end

    if base_fans do
      all_tiles = hand ++ Enum.flat_map(melds, & &1.tiles)

      fans =
        base_fans
        |> append_fan(:pure_suit, pure_suit?(all_tiles))
        |> append_fan(:self_draw, :self_draw in flags)
        |> append_fan(:heavenly, :heavenly in flags)
        |> append_fan(:earthly, :earthly in flags)
        |> append_fan(:kong_blossom, :kong_blossom in flags)
        |> Enum.reverse()

      {:win, fans, length(fans)}
    else
      :no_win
    end
  end

  # 标准牌型：暗牌分解为 (4 - 副露数) 副刻/顺 + 一对将。
  # 碰碰胡：副露无吃且暗牌可全刻分解，任意将；
  # 平胡：将必须 2/5/8。
  defp standard_win(hand, melds) do
    counts = count_map(hand)
    sets_needed = 4 - length(melds)

    melds_all_pung? =
      Enum.all?(melds, &(&1.type in [:pong, :kong_open, :kong_concealed, :kong_added]))

    pair_keys =
      for {{suit, value}, count} <- counts, count >= 2, do: {suit, value}

    # 碰碰胡：暗牌全刻分解 + 副露全刻
    pung_pung_win? =
      melds_all_pung? and
        Enum.any?(pair_keys, fn pair ->
          counts |> Map.update!(pair, &(&1 - 2)) |> decomposable_pung?(sets_needed)
        end)

    if pung_pung_win? do
      [:pung_pung]
    else
      # 平胡：258 将 + 顺/刻混合分解
      pma_pair? =
        Enum.any?(pair_keys, fn {_suit, value} = pair ->
          value in [2, 5, 8] and
            counts |> Map.update!(pair, &(&1 - 2)) |> decomposable?(sets_needed)
        end)

      if pma_pair?, do: [:ping_hu]
    end
  end

  # 只用刻子分解
  defp decomposable_pung?(counts, 0), do: Enum.all?(counts, fn {_key, count} -> count == 0 end)

  defp decomposable_pung?(counts, n) when n > 0 do
    counts
    |> Enum.reject(fn {_key, count} -> count <= 0 end)
    |> Map.new()
    |> case do
      counts when map_size(counts) == 0 ->
        false

      counts ->
        Enum.all?(counts, fn {_key, count} -> rem(count, 3) == 0 end) and
          Enum.sum(Map.values(counts)) == 3 * n
    end
  end

  # counts 是否恰好分解为 n 副刻子/顺子
  defp decomposable?(counts, 0), do: Enum.all?(counts, fn {_key, count} -> count == 0 end)

  defp decomposable?(counts, n) when n > 0 do
    counts =
      counts
      |> Enum.reject(fn {_key, count} -> count <= 0 end)
      |> Map.new()

    if map_size(counts) == 0 do
      false
    else
      {{suit, value} = key, count} = Enum.min_by(counts, fn {k, _} -> k end)

      cond do
        # 刻子
        count >= 3 ->
          decomposable?(Map.update!(counts, key, &(&1 - 3)), n - 1)

        # 顺子（同花色 v, v+1, v+2）
        value + 2 <= 9 and tile_count(counts, suit, value + 1) >= 1 and
            tile_count(counts, suit, value + 2) >= 1 ->
          counts
          |> Map.update!(key, &(&1 - 1))
          |> Map.update!({suit, value + 1}, &(&1 - 1))
          |> Map.update!({suit, value + 2}, &(&1 - 1))
          |> then(&decomposable?(&1, n - 1))

        true ->
          false
      end
    end
  end

  defp tile_count(counts, suit, value), do: Map.get(counts, {suit, value}, 0)

  defp seven_pairs?(hand, melds) do
    melds == [] and
      hand
      |> Enum.frequencies_by(&Tile.key/1)
      |> Map.values()
      |> then(fn counts -> length(counts) == 7 and Enum.all?(counts, &(&1 == 2)) end)
  end

  defp pure_suit?(tiles) do
    tiles != [] and Enum.all?(tiles, &(&1.suit == hd(tiles).suit))
  end

  defp count_map(tiles) do
    suits = Tile.suits()
    values = Enum.to_list(1..9)

    base =
      for suit <- suits, value <- values, into: %{} do
        {{suit, value}, 0}
      end

    Enum.reduce(tiles, base, fn tile, acc ->
      Map.update!(acc, Tile.key(tile), &(&1 + 1))
    end)
  end

  @doc """
  某玩家对弃牌可执行的动作（胡 > 碰/杠 > 吃）。

  返回如 `[:win, :pong, {:kong_open}, {:chow, 3}]`。
  """
  @spec claim_actions([Tile.t()], [meld()], Tile.t()) :: [
          :win | :pong | {:kong_open} | {:chow, pos_integer()}
        ]
  def claim_actions(hand, melds, tile) do
    actions = []

    actions =
      if match?({:win, _, _}, check(hand ++ [tile], melds)), do: [:win | actions], else: actions

    actions =
      if Tile.count(hand, tile) >= 2, do: [:pong | actions], else: actions

    actions =
      if Tile.count(hand, tile) >= 3, do: [{:kong_open} | actions], else: actions

    chows =
      for base <- [tile.value - 2, tile.value - 1, tile.value],
          base >= 1 and base + 2 <= 9,
          has?(hand, tile.suit, base),
          has?(hand, tile.suit, base + 1),
          has?(hand, tile.suit, base + 2),
          # 弃牌本身占一格，手牌只需提供另外两张
          count_in_combo(hand, tile, base) >= 2,
          do: {:chow, base}

    (actions ++ chows) |> Enum.uniq()
  end

  defp count_in_combo(hand, tile, base) do
    Enum.count(hand, fn t ->
      t.suit == tile.suit and t.value in [base, base + 1, base + 2]
    end)
  end

  @doc """
  当前轮到自己（手牌 14 张或副露后 13+1）时可执行的动作。

  返回如 `[:win, {:kong_concealed, tile}, {:kong_added, tile}]`。
  """
  @spec self_actions([Tile.t()], [meld()]) :: [
          :win | {:kong_concealed, Tile.t()} | {:kong_added, Tile.t()}
        ]
  def self_actions(hand, melds) do
    actions =
      case check(hand, melds) do
        {:win, _, _} -> [:win]
        :no_win -> []
      end

    concealed_kongs =
      for {{suit, value}, count} <- hand |> count_map_no_fill(),
          count == 4,
          do: {:kong_concealed, %Tile{id: "candidate", suit: suit, value: value}}

    added_kongs =
      for meld <- melds,
          meld.type == :pong,
          tile = hd(meld.tiles),
          Tile.count(hand, tile) >= 1,
          do: {:kong_added, tile}

    actions ++ concealed_kongs ++ added_kongs
  end

  defp count_map_no_fill(tiles) do
    Enum.frequencies_by(tiles, &Tile.key/1)
  end

  defp has?(hand, suit, value) do
    Enum.any?(hand, &(&1.suit == suit and &1.value == value))
  end

  defp append_fan(fans, _fan, false), do: fans
  defp append_fan(fans, fan, true), do: [fan | fans]
end
