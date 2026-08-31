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
    jiang_jiang_hu: "将将胡",
    seven_pairs: "七对",
    pure_suit: "清一色",
    quan_qiu_ren: "全求人",
    self_draw: "自摸",
    heavenly: "天胡",
    earthly: "地胡",
    kong_blossom: "杠上开花"
  }

  @type fan ::
          :ping_hu
          | :pung_pung
          | :jiang_jiang_hu
          | :seven_pairs
          | :pure_suit
          | :quan_qiu_ren
          | flag()

  # 番值：大牌型权重更高（全求人/将将胡为牌型番，非简单叠加）
  @fan_values %{
    ping_hu: 1,
    pung_pung: 2,
    jiang_jiang_hu: 4,
    seven_pairs: 4,
    pure_suit: 4,
    quan_qiu_ren: 6,
    self_draw: 1,
    heavenly: 10,
    earthly: 10,
    kong_blossom: 1
  }

  @spec fan_name(fan()) :: String.t()
  def fan_name(fan), do: Map.fetch!(@fan_names, fan)

  @doc """
  判定 14 张牌（手牌 + 副露）是否胡牌。

  返回 `{:win, fans, score}`，番数 = 番型数量；不胡返回 `:no_win`。
  """
  @spec check([Tile.t()], [meld()], [flag()]) :: {:win, [fan()], pos_integer()} | :no_win

  # 五种独立牌型：全求人 / 将将胡 / 碰碰胡 / 清一色 / 七小对。
  # 同时命中多型则全部叠加计番（如全求人将将胡、碰碰胡将将胡、清一色碰碰胡）。
  # 平胡（258 做【将】）为底：未被更高牌型包含时单独计番。
  def check(hand, melds \\ [], flags \\ []) do
    all_tiles = hand ++ Enum.flat_map(melds, & &1.tiles)
    jj? = jiang_jiang?(all_tiles)
    pung_pung? = pung_pung_shape?(hand, melds)
    pure_suit? = pure_suit_shape?(hand, melds)
    seven_pairs? = seven_pairs?(hand, melds)

    # 全求人：四组副露（吃碰杠皆可）+ 单钓将——无论点炮还是自摸，
    # 和的那张必须与手中最后一张同牌；大牌 6 番
    quan_qiu? = quan_qiu_ren?(hand, melds)

    # 平胡：258 做【将】的顺/刻分解；被碰碰胡/将将胡/全求人包含时不单独叫
    ping_hu? = ping_hu_shape?(hand, melds) and not pung_pung? and not jj? and not quan_qiu?

    win? =
      seven_pairs? or jj? or quan_qiu? or pung_pung? or pure_suit? or ping_hu?

    if win? do
      fans =
        []
        |> append_fan(:seven_pairs, seven_pairs?)
        |> append_fan(:jiang_jiang_hu, jj?)
        |> append_fan(:quan_qiu_ren, quan_qiu?)
        |> append_fan(:pung_pung, pung_pung?)
        |> append_fan(:pure_suit, pure_suit?)
        |> append_fan(:ping_hu, ping_hu?)
        |> append_fan(:self_draw, :self_draw in flags)
        |> append_fan(:heavenly, :heavenly in flags)
        |> append_fan(:earthly, :earthly in flags)
        |> append_fan(:kong_blossom, :kong_blossom in flags)
        |> Enum.reverse()

      score = fans |> Enum.map(&Map.fetch!(@fan_values, &1)) |> Enum.sum()

      {:win, fans, score}
    else
      :no_win
    end
  end

  # 全求人：四组副露（吃碰杠皆可）+ 单钓将——和的那张必须与手中
  # 最后一张同牌；点炮与自摸皆计大牌 6 番
  defp quan_qiu_ren?(hand, melds) do
    length(melds) == 4 and
      length(hand) == 2 and
      Tile.same?(hd(hand), hd(tl(hand)))
  end

  # 将将胡：手牌与副露的所有牌均为 2/5/8（不要求能分解成对子/刻顺；
  # 整副牌 ≥14 张，杠手会多出替换张）
  defp jiang_jiang?(all_tiles) do
    length(all_tiles) >= 14 and Enum.all?(all_tiles, &(&1.value in [2, 5, 8]))
  end

  # 碰碰胡：副露全为刻/杠 + 暗牌可全刻分解 + 任意一对做将
  defp pung_pung_shape?(hand, melds) do
    melds_all_pung? =
      Enum.all?(melds, &(&1.type in [:pong, :kong_open, :kong_concealed, :kong_added]))

    melds_all_pung? and decomposable_with_pair?(hand, melds, :pung_only)
  end

  # 清一色：同花色 + 任意一对做将的顺/刻分解（不要求 258）
  defp pure_suit_shape?(hand, melds) do
    pure_suit?(hand ++ Enum.flat_map(melds, & &1.tiles)) and
      decomposable_with_pair?(hand, melds, :any)
  end

  # 平胡：258 做将的顺/刻分解
  defp ping_hu_shape?(hand, melds), do: decomposable_with_pair?(hand, melds, 258)

  defp decomposable_with_pair?(hand, melds, pair_rule) do
    counts = count_map(hand)
    sets_needed = 4 - length(melds)

    pair_keys =
      for {{suit, value}, count} <- counts, count >= 2, do: {suit, value}

    Enum.any?(pair_keys, fn {_suit, value} = pair ->
      pair_ok? =
        case pair_rule do
          :pung_only -> true
          :any -> true
          258 -> value in [2, 5, 8]
        end

      pair_ok? and counts |> Map.update!(pair, &(&1 - 2)) |> decompose_melds?(sets_needed, pair_rule)
    end)
  end

  defp decompose_melds?(counts, n, :pung_only), do: decomposable_pung?(counts, n)
  defp decompose_melds?(counts, n, _pair_rule), do: decomposable?(counts, n)

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

    # 吃：手牌提供顺子中除弃牌外的另外两张（弃牌本身来自别家）
    chows =
      for base <- [tile.value - 2, tile.value - 1, tile.value],
          base >= 1 and base + 2 <= 9,
          needed = Enum.reject(base..(base + 2), &(&1 == tile.value)),
          Enum.all?(needed, &has?(hand, tile.suit, &1)),
          do: {:chow, base}

    (actions ++ chows) |> Enum.uniq()
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
