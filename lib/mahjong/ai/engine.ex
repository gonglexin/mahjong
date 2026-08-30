defmodule Mahjong.AI.Engine do
  @moduledoc """
  AI 决策引擎：向听数计算 + 性格化选择。

  三种性格：
    * `:greedy`  大牌型（豪哥）——愿意放弃小胡去争取清一色/碰碰胡/七对等大牌
    * `:rational` 科学型（教授）——一切以牌面与概率计算，向听数最优
    * `:casual`  随性型（乐乐）——打得随意，带点随机
  """

  alias Mahjong.{Player, Rules, Tile}

  # -- 向听数 -------------------------------------------------------------------

  @doc """
  标准牌型向听数（含副露）。副露以 meld 列表计入面子数。
  返回 8 - 2*面子 - 搭子（-1 即和牌）。
  """
  def shanten(hand, melds) do
    counts = frequencies(hand)
    meld_count = length(melds)
    {sets, partials} = best_blocks(counts)

    base = 8 - 2 * (meld_count + sets) - partials
    # 搭子+面子 超过 5 组时修正（多搭无用）
    over = max(0, meld_count + sets + partials - 5)

    # 无雀头修正：5 块齐但缺对子时，实际还差一步
    no_pair? =
      not Enum.any?(counts, fn {_k, n} -> n >= 2 end) and
        not Enum.any?(melds, &(&1.type == :pong))

    sh = base + over + if(meld_count + sets + partials >= 5 and no_pair?, do: 1, else: 0)
    max(sh, -1)
  end

  # 递归分解：对每张牌依次尝试 不用/对子/刻子/顺子，记录最优 {面子, 搭子}
  defp best_blocks(counts) do
    keys =
      counts
      |> Enum.reject(fn {_k, n} -> n == 0 end)
      |> Enum.map(fn {{s, v}, _} -> {Tile.suit_rank(s), v, s, v} end)
      |> Enum.sort()
      |> Enum.map(fn {_r, _v, s, v} -> {s, v} end)

    best = scan(keys, counts, 0, 0)
    best
  end

  defp scan([], _counts, sets, partials), do: {sets, partials}

  # 块数上限：4 面子 + 1 将
  defp scan([_key | _rest], _counts, sets, _partials) when sets > 4, do: {4, 0}

  defp scan([key | rest], counts, sets, partials) do
    n = Map.get(counts, key, 0)
    # 本张不参与任何块
    best = scan(rest, counts, sets, partials)

    {suit, value} = key

    # 对子（搭子）
    best =
      if n >= 2 and sets + partials < 5 do
        max(best, scan(rest, remove(counts, key, 2), sets, partials + 1))
      else
        best
      end

    # 刻子（面子）
    best =
      if n >= 3 and sets < 4 do
        max(best, scan([key | rest], remove(counts, key, 3), sets + 1, partials))
      else
        best
      end

    # 顺子（面子）
    best =
      if (suit && value + 2 <= 9) and tile_n(counts, suit, value + 1) > 0 and
           tile_n(counts, suit, value + 2) > 0 and sets < 4 do
        c =
          counts
          |> Map.update!(key, &(&1 - 1))
          |> Map.update!({suit, value + 1}, &(&1 - 1))
          |> Map.update!({suit, value + 2}, &(&1 - 1))

        max(best, scan(rest, c, sets + 1, partials))
      else
        best
      end

    # 两面搭子 k,k+1（搭子）
    best =
      if (suit && value + 1 <= 9) and tile_n(counts, suit, value + 1) > 0 and
           sets + partials < 5 do
        c =
          counts
          |> Map.update!(key, &(&1 - 1))
          |> Map.update!({suit, value + 1}, &(&1 - 1))

        max(best, scan(rest, c, sets, partials + 1))
      else
        best
      end

    # 坎张搭子 k,k+2（搭子）
    best =
      if (suit && value + 2 <= 9) and tile_n(counts, suit, value + 1) == 0 and
           tile_n(counts, suit, value + 2) > 0 and sets + partials < 5 do
        c =
          counts
          |> Map.update!(key, &(&1 - 1))
          |> Map.update!({suit, value + 2}, &(&1 - 1))

        max(best, scan(rest, c, sets, partials + 1))
      else
        best
      end

    best
  end

  defp tile_n(counts, suit, value), do: Map.get(counts, {suit, value}, 0)

  defp remove(counts, key, n), do: Map.update!(counts, key, &max(&1 - n, 0))

  defp frequencies(tiles) do
    Enum.frequencies_by(tiles, &Tile.key/1)
  end

  # -- 打牌选择 -----------------------------------------------------------------

  @doc """
  自己回合的决策（已摸牌，13/14 张）。返回：
    * `:win` — 自摸胡
    * `{:kong_concealed, tile}` / `{:kong_added, tile}` — 杠
    * `{:discard, tile}` — 出牌
  """
  def decide_self(%Player{persona: persona} = player, state_ctx) do
    actions = Rules.self_actions(player.hand, player.open_hand)

    cond do
      :win in actions ->
        if decline_win?(persona, player, state_ctx),
          do: discard_choice(persona, player, state_ctx),
          else: :win

      kong = Enum.find(actions, &match?({:kong_concealed, _}, &1)) ->
        if persona in [:greedy, :rational],
          do: kong,
          else: discard_choice(persona, player, state_ctx)

      kong = Enum.find(actions, &match?({:kong_added, _}, &1)) ->
        if persona != :casual, do: kong, else: discard_choice(persona, player, state_ctx)

      true ->
        discard_choice(persona, player, state_ctx)
    end
  end

  # 大牌型：小胡（仅平胡类 1 番）且牌型潜力大、牌墙还多时，放弃自摸去追大牌
  defp decline_win?(:greedy, player, state_ctx) do
    case Rules.check(player.hand, player.open_hand, [:self_draw]) do
      {:win, fans, score} ->
        big_fan? =
          Enum.any?(
            fans,
            &(&1 in [
                :pung_pung,
                :jiang_jiang_hu,
                :seven_pairs,
                :pure_suit,
                :quan_qiu_ren
              ])
          )

        low_value? = score <= 2 and not big_fan?

        low_value? and hand_potential(player.hand, player.open_hand) >= 2 and
          state_ctx.wall_left >= 18

      :no_win ->
        false
    end
  end

  defp decline_win?(_, _, _), do: false

  defp discard_choice(persona, player, state_ctx) do
    hand = player.hand

    candidates =
      hand
      |> Enum.uniq_by(&Tile.key/1)
      |> Enum.map(fn tile ->
        rest = Tile.remove_one(hand, tile)
        sh = shanten(rest, player.open_hand)
        danger = discard_danger(tile, state_ctx)
        keep_score = tile_keep_value(tile, rest, player.open_hand)
        {tile, sh, danger, keep_score}
      end)

    best_shanten = candidates |> Enum.map(fn {_, sh, _, _} -> sh end) |> Enum.min()

    pool = Enum.filter(candidates, fn {_, sh, _, _} -> sh == best_shanten end)

    case persona do
      :rational ->
        # 向听最优 → 弃危险度最低 → 保留价值
        Enum.min_by(pool, fn {_, _, danger, keep} -> {danger, -keep} end)

      :greedy ->
        # 优先保留构成大牌潜力的牌（邻张/对子越多越留），再按危险度
        Enum.min_by(pool, fn {tile, _, danger, _} ->
          {-tile_keep_value(tile, Tile.remove_one(hand, tile), []), danger}
        end)

      :casual ->
        Enum.random(pool)

      _ ->
        Enum.min_by(pool, fn {_, _, danger, _} -> danger end)
    end
    |> then(fn {tile, _sh, _danger, _keep} -> {:discard, tile} end)
  end

  # 弃牌危险度：中张牌更容易被别家碰/吃，危险度高
  defp discard_danger(tile, _ctx) do
    v = tile.value

    base =
      cond do
        v in [1, 9] -> 0
        v in [2, 8] -> 1
        v in [3, 7] -> 2
        true -> 3
      end

    # 已见的同类牌越多，越安全
    base
  end

  defp tile_keep_value(tile, rest, _melds) do
    {suit, value} = Tile.key(tile)

    neighbors =
      for dv <- [-2, -1, 1, 2],
          v when v in 1..9 <- [value + dv],
          do: Map.get(frequencies(rest), {suit, v}, 0)

    same = Map.get(frequencies(rest), {suit, value}, 0)

    Enum.sum(neighbors) * 2 + same * 3
  end

  # -- 报牌决策 -----------------------------------------------------------------

  @doc "对弃牌的报牌决策（actions 为该阶段合法动作）。返回 :pass 或动作。"
  def decide_claim(persona, player, tile, actions, state_ctx) do
    cond do
      :win in actions ->
        if persona == :greedy and
             decline_win?(persona, %{player | hand: player.hand ++ [tile]}, state_ctx) do
          claim_or_pass(persona, player, tile, List.delete(actions, :win), state_ctx)
        else
          :win
        end

      true ->
        claim_or_pass(persona, player, tile, actions, state_ctx)
    end
  end

  defp claim_or_pass(persona, player, tile, actions, _state_ctx) do
    sh_before = shanten(player.hand, player.open_hand)

    pong_ok? = fn ->
      :pong in actions and
        shanten(
          player.hand |> Tile.remove_one(tile) |> Tile.remove_one(tile),
          player.open_hand ++ [%{type: :pong, tiles: List.duplicate(tile, 3), from: nil}]
        ) < sh_before
    end

    chow_ok? = fn ->
      chows = Enum.filter(actions, &match?({:chow, _}, &1))

      Enum.any?(chows, fn {:chow, base} ->
        tiles = for v <- base..(base + 2), v != tile.value, do: %{tile | value: v}

        hand_after =
          Enum.reduce(tiles, player.hand, fn t, acc -> Tile.remove_one(acc, t) end)

        meld = %{type: :chow, tiles: [tile | tiles], from: nil}
        shanten(hand_after, player.open_hand ++ [meld]) < sh_before
      end)
    end

    cond do
      :pong in actions and persona != :greedy ->
        :pong

      :pong in actions and pong_ok?.() ->
        :pong

      true ->
        chow_wanted? =
          chow_ok?.() and
            (persona == :rational or (persona == :casual and :rand.uniform(3) == 1))

        if chow_wanted? do
          {:chow, chow_base(tile, player.hand)}
        else
          :pass
        end
    end
  end

  defp chow_base(tile, hand) do
    [tile.value - 2, tile.value - 1, tile.value]
    |> Enum.filter(fn base ->
      base >= 1 and base + 2 <= 9 and
        Enum.all?(for(v <- base..(base + 2), v != tile.value, do: v), fn v ->
          Tile.count(hand, %{tile | value: v}) >= 1
        end)
    end)
    |> List.first()
  end

  # -- 牌型潜力 -----------------------------------------------------------------

  @doc "估算做大牌的潜力分：清一色/碰碰胡/七对雏形越高越值得追。"
  def hand_potential(hand, melds) do
    counts = frequencies(hand)
    total = Enum.sum(Map.values(counts))
    all_tiles = hand ++ Enum.flat_map(melds, & &1.tiles)

    max_suit_count =
      Tile.suits()
      |> Enum.map(fn s -> Enum.count(all_tiles, &(&1.suit == s)) end)
      |> Enum.max()

    pairs_and_triplets =
      Enum.count(counts, fn {_k, n} -> n >= 2 end)

    score = 0
    score = if total >= 8 and max_suit_count / max(total, 1) >= 0.65, do: score + 2, else: score
    score = if pairs_and_triplets >= 3, do: score + 2, else: score
    score = if pairs_and_triplets >= 4, do: score + 1, else: score
    score
  end

  def shanten_for(player), do: shanten(player.hand, player.open_hand)
end
