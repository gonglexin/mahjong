defmodule Mahjong.RulesTest do
  use ExUnit.Case, async: true

  alias Mahjong.Rules

  defp tile(suit, value, id \\ nil),
    do: %Mahjong.Tile{id: id || "#{suit}-#{value}-:rand.unique()", suit: suit, value: value}

  defp seq(suit, base), do: for(v <- base..(base + 2), do: tile(suit, v))
  defp triplet(suit, v), do: List.duplicate(tile(suit, v), 3)
  defp pair(suit, v), do: List.duplicate(tile(suit, v), 2)

  describe "check/3" do
    test "平胡：四顺子 + 258 将" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          seq(:dots, 2) ++ pair(:characters, 5)

      assert {:win, fans, _} = Rules.check(hand)
      assert :ping_hu in fans
    end

    test "非 258 将的顺子牌型不胡" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          seq(:dots, 2) ++ pair(:characters, 9)

      assert :no_win = Rules.check(hand)
    end

    test "碰碰胡：全刻子任意将" do
      hand =
        triplet(:characters, 1) ++
          triplet(:characters, 3) ++
          triplet(:dots, 5) ++ triplet(:bamboos, 7) ++ pair(:dots, 9)

      assert {:win, fans, _} = Rules.check(hand)
      assert :pung_pung in fans
    end

    test "七对" do
      hand =
        Enum.flat_map([1, 2, 3, 4, 5, 6, 7], &pair(:bamboos, &1))

      assert {:win, fans, _} = Rules.check(hand)
      assert :seven_pairs in fans
    end

    test "清一色：全万" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          triplet(:characters, 9) ++ pair(:characters, 5)

      assert {:win, fans, _} = Rules.check(hand)
      assert :pure_suit in fans
      assert :ping_hu in fans
    end

    test "自摸附加番" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          seq(:dots, 2) ++ pair(:characters, 5)

      assert {:win, fans, _} = Rules.check(hand, [], [:self_draw])
      assert :self_draw in fans
    end

    test "副露与暗牌合计成牌（碰出 9筒 后）" do
      meld = %{type: :pong, tiles: triplet(:dots, 9), from: "p1"}

      hand =
        seq(:characters, 1) ++ seq(:characters, 4) ++ seq(:characters, 7) ++ pair(:characters, 2)

      assert {:win, fans, _} = Rules.check(hand, [meld])
      assert :ping_hu in fans
    end

    test "七对要求门清" do
      meld = %{type: :pong, tiles: triplet(:dots, 9), from: "p1"}
      hand = Enum.flat_map([1, 2, 3, 4, 5], &pair(:bamboos, &1)) ++ pair(:bamboos, 6)

      assert :no_win = Rules.check(hand, [meld])
    end
  end

  describe "全求人 / 将将胡" do
    test "全求人：四组碰 + 手牌单张成对，不限将" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 1), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 3), from: "p"},
        %{type: :kong_open, tiles: List.duplicate(tile(:bamboos, 7), 4), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 9), from: "p"}
      ]

      hand = pair(:bamboos, 4)

      assert {:win, fans, _score} = Rules.check(hand, melds)
      assert :quan_qiu_ren in fans
      assert :pung_pung in fans
      # 不限 258 将：4 条做将也成立
    end

    test "手牌两张不同或副露含吃时不是全求人" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 1), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 3), from: "p"},
        %{type: :chow, tiles: seq(:bamboos, 2), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 9), from: "p"}
      ]

      hand = pair(:bamboos, 4)
      assert :no_win = Rules.check(hand, melds)

      hand2 = [tile(:bamboos, 4), tile(:dots, 4)]
      melds2 = Enum.map(melds, &%{&1 | type: :pong})
      assert :no_win = Rules.check(hand2, melds2)
    end

    test "将将胡：全部为 2/5/8 的刻子与将" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 2), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 5), from: "p"},
        %{type: :pong, tiles: triplet(:bamboos, 8), from: "p"}
      ]

      hand = pair(:bamboos, 2) ++ pair(:characters, 5)

      assert Enum.count(hand) == 4

      # 胡 2 条：222 条成刻，55万 做将 → 将将胡
      assert {:win, fans, _} = Rules.check(hand ++ [tile(:bamboos, 2)], melds)
      assert :jiang_jiang_hu in fans
      assert :pung_pung in fans

      # 胡 5 万：555 万成刻，22条 做将 → 两张不同的将均可胡
      assert {:win, fans2, _} = Rules.check(hand ++ [tile(:characters, 5)], melds)
      assert :jiang_jiang_hu in fans2
    end

    test "副露含非将刻子时不是将将胡" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 3), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 5), from: "p"},
        %{type: :pong, tiles: triplet(:bamboos, 8), from: "p"}
      ]

      hand = pair(:dots, 2) ++ pair(:bamboos, 2)

      assert Enum.count(hand) == 4

      assert {:win, fans, _} = Rules.check(hand ++ [tile(:bamboos, 2)], melds)
      assert :pung_pung in fans
      refute :jiang_jiang_hu in fans
    end

    test "全求人+将将胡 叠加计分" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 2), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 5), from: "p"},
        %{type: :kong_concealed, tiles: List.duplicate(tile(:bamboos, 8), 4), from: nil},
        %{type: :pong, tiles: triplet(:dots, 2), from: "p"}
      ]

      hand = pair(:characters, 5)

      assert {:win, fans, score} = Rules.check(hand, melds, [:self_draw])
      assert :quan_qiu_ren in fans
      assert :jiang_jiang_hu in fans

      expected =
        fans
        |> Enum.map(&Rules.fan_name/1)
        |> length()

      assert score == expected or score > 6
    end
  end

  describe "claim_actions/3" do
    test "可碰可吃（无胡）" do
      hand =
        List.duplicate(tile(:characters, 5), 2) ++
          [
            tile(:characters, 3),
            tile(:characters, 4),
            tile(:characters, 6),
            tile(:characters, 7)
          ] ++
          for v <- 1..7, do: tile(:dots, v)

      actions = Rules.claim_actions(hand, [], tile(:characters, 5))

      assert :win not in actions
      assert :pong in actions
      assert {:chow, 3} in actions
      assert {:chow, 4} in actions
      assert {:chow, 5} in actions
    end

    test "claimed tile completes the hand for win" do
      hand =
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++
          [tile(:dots, 2), tile(:dots, 3)] ++ pair(:dots, 5)

      assert :win in Rules.claim_actions(hand, [], tile(:dots, 4))
    end
  end

  describe "self_actions/2" do
    test "暗杠候选" do
      hand = List.duplicate(tile(:bamboos, 4), 4) ++ List.duplicate(tile(:dots, 5), 10)
      [action] = Rules.self_actions(hand, [])
      assert {:kong_concealed, _} = action
    end

    test "加杠候选" do
      meld = %{type: :pong, tiles: triplet(:dots, 9), from: "p1"}
      hand = [tile(:dots, 9)] ++ seq(:characters, 1) ++ seq(:characters, 4) ++ seq(:bamboos, 7)

      assert {:kong_added, tile} = Rules.self_actions(hand, [meld]) |> List.last()
      assert tile.value == 9
    end
  end
end
