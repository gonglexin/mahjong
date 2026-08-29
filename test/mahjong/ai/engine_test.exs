defmodule Mahjong.AI.EngineTest do
  use ExUnit.Case, async: true

  alias Mahjong.AI.Engine
  alias Mahjong.{Player, Tile}

  @suffix :erlang.unique_integer([:positive])

  defp tile(suit, value),
    do: %Tile{
      id: "#{suit}#{value}-#{:erlang.unique_integer([:positive])}",
      suit: suit,
      value: value
    }

  defp seq(suit, base), do: for(v <- base..(base + 2), do: tile(suit, v))
  defp pair(suit, v), do: List.duplicate(tile(suit, v), 2)
  defp triplet(suit, v), do: List.duplicate(tile(suit, v), 3)
  defp filler(n), do: for(i <- 1..n, do: tile(:bamboos, rem(i, 9) + 1))

  defp player(persona, hand, melds \\ []) do
    %{Player.new(persona: persona) | hand: hand, open_hand: melds}
  end

  describe "shanten/2" do
    test "和牌型向听数为 -1" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++ seq(:characters, 7) ++ seq(:dots, 2) ++ pair(:dots, 5)

      assert Engine.shanten(hand, []) == -1
    end

    test "听牌（差一张）向听数为 0" do
      # 123万 456万 789万 + 2筒3筒4筒 + 5筒单张 → 听 5 筒（对倒）
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          seq(:dots, 2) ++ [tile(:dots, 5)]

      assert Engine.shanten(hand, []) == 0
    end

    test "副露计入面子数" do
      meld = %{type: :pong, tiles: triplet(:dots, 9), from: "p"}

      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++ seq(:characters, 7) ++ [tile(:dots, 5), tile(:dots, 5)]

      # 3 副露 + 手牌 123/456/789 + 55 将 = 和
      assert Engine.shanten(hand, [meld]) == -1
    end

    test "散牌向听数较高" do
      hand =
        for(v <- [1, 4, 7], do: tile(:characters, v)) ++
          for(v <- [2, 5, 8], do: tile(:dots, v)) ++
          for(v <- [3, 6, 9], do: tile(:bamboos, v)) ++ [tile(:characters, 2), tile(:dots, 5)]

      assert Engine.shanten(hand, []) >= 2
    end
  end

  describe "decide_self/2" do
    test "科学型：能自摸就胡" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          seq(:dots, 2) ++ pair(:dots, 5)

      assert Enum.count(hand) == 14
      p = player(:rational, hand)
      assert Engine.decide_self(p, %{wall_left: 30}) == :win
    end

    test "大牌型：潜力一般时小胡也胡" do
      # 三色均衡的 14 张平胡自摸，没有大牌潜力 → 直接胡
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          seq(:dots, 2) ++ pair(:bamboos, 5)

      assert Enum.count(hand) == 14
      assert match?({:win, _, _}, Mahjong.Rules.check(hand, [], [:self_draw]))
      assert Engine.hand_potential(hand, []) == 0

      p = player(:greedy, hand)
      assert Engine.decide_self(p, %{wall_left: 30}) == :win
    end

    test "大牌型：混色潜力大时放弃 1 番小胡" do
      # 万子 11 张清一色雏形 + 234 筒顺：平胡自摸只有 1-2 番，潜力高 → 放弃去追清一色
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++ pair(:characters, 5) ++ seq(:dots, 2)

      assert Enum.count(hand) == 14
      p = player(:greedy, hand)
      ctx = %{wall_left: 40}

      assert {:win, fans, score} = Mahjong.Rules.check(hand, [], [:self_draw])
      assert score <= 2 and not Enum.any?(fans, &(&1 in [:pung_pung, :seven_pairs, :pure_suit]))
      assert Engine.hand_potential(hand, []) >= 2

      assert {:discard, _} = Engine.decide_self(p, ctx)
    end

    test "科学型与其他性格：有暗杠就杠" do
      hand =
        List.duplicate(tile(:bamboos, 4), 4) ++ for(i <- 1..10, do: tile(:dots, rem(i, 9) + 1))

      assert Enum.count(hand) == 14
      p = player(:rational, hand)
      assert {:kong_concealed, _} = Engine.decide_self(p, %{wall_left: 30})
    end
  end

  describe "decide_claim/4" do
    test "科学型：碰能改善向听则碰" do
      claimed = tile(:characters, 5)

      hand =
        pair(:characters, 5) ++
          pair(:dots, 1) ++
          seq(:dots, 2) ++
          seq(:bamboos, 1) ++ [tile(:bamboos, 8), tile(:bamboos, 9), tile(:characters, 1)]

      assert Enum.count(hand) == 13
      p = player(:rational, hand)
      assert Engine.decide_claim(:rational, p, claimed, [:pong], %{wall_left: 30}) == :pong
    end

    test "科学型：吃能改善向听则吃" do
      claimed = tile(:characters, 5)

      hand =
        [tile(:characters, 3), tile(:characters, 4)] ++
          seq(:bamboos, 1) ++
          [tile(:bamboos, 8), tile(:bamboos, 8), tile(:bamboos, 9), tile(:bamboos, 9)] ++
          [tile(:dots, 1), tile(:dots, 2)] ++ [tile(:dots, 8), tile(:dots, 9)]

      assert Enum.count(hand) == 13
      p = player(:rational, hand)

      assert {:chow, 3} =
               Engine.decide_claim(:rational, p, claimed, [{:chow, 3}], %{wall_left: 30})
    end

    test "大牌型：有清一色/碰碰胡潜力时放弃吃（保持牌型）" do
      claimed = tile(:characters, 5)

      # 全万子 + 3,4万 —— 吃 5 万会破坏清一色雏形（吃进 5 万其实是万子……构造全筒子+3,4万）
      hand =
        [tile(:characters, 3), tile(:characters, 4)] ++
          for(v <- [1, 1, 2, 4, 5, 6, 7, 8, 9, 9, 5], do: tile(:dots, v))

      assert Enum.count(hand) == 13
      p = player(:greedy, hand)
      assert Engine.decide_claim(:greedy, p, claimed, [{:chow, 3}], %{wall_left: 40}) == :pass
    end

    test "随性型：总是胡" do
      claimed = tile(:dots, 2)

      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++ [tile(:dots, 2), tile(:dots, 2), tile(:dots, 3), tile(:dots, 4)]

      assert Enum.count(hand) == 13
      p = player(:casual, hand)
      assert Engine.decide_claim(:casual, p, claimed, [:win], %{wall_left: 30}) == :win
    end

    test "无法改善向听时过牌" do
      claimed = tile(:bamboos, 4)
      hand = seq(:characters, 1) ++ pair(:dots, 2) ++ for(v <- 2..9, do: tile(:dots, v))

      assert Enum.count(hand) == 13
      p = player(:rational, hand)
      assert Engine.decide_claim(:rational, p, claimed, [{:chow, 4}], %{wall_left: 30}) == :pass
    end
  end

  describe "hand_potential/2" do
    test "清一色雏形潜力高" do
      hand =
        for(v <- [1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9], do: tile(:characters, v)) ++
          [tile(:dots, 3), tile(:dots, 7)]

      assert Engine.hand_potential(hand, []) >= 2
    end

    test "对子多时碰碰胡潜力高" do
      hand =
        pair(:characters, 1) ++
          pair(:dots, 3) ++ pair(:bamboos, 5) ++ seq(:dots, 6) ++ [tile(:characters, 9)]

      assert Engine.hand_potential(hand, []) >= 2
    end
  end
end
