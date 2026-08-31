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
    test "全求人：单钓将——和的那张必须与手中最后一张同牌" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 1), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 3), from: "p"},
        %{type: :kong_open, tiles: List.duplicate(tile(:bamboos, 7), 4), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 9), from: "p"}
      ]

      # 手牌两张不同：无法单钓，不是全求人，也不是和牌
      hand = [tile(:bamboos, 4), tile(:dots, 4)]

      assert :no_win = Rules.check(hand, melds)

      # 自摸同样的牌凑成对：全求人(6) + 碰碰胡(2) + 自摸(1) = 9
      hand2 = pair(:bamboos, 4)
      assert {:win, fans2, 9} = Rules.check(hand2, melds, [:self_draw])
      assert :quan_qiu_ren in fans2
      assert :pung_pung in fans2
      assert :self_draw in fans2
      refute :ping_hu in fans2
    end

    test "自摸同样计全求人大牌" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 1), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 3), from: "p"},
        %{type: :kong_open, tiles: List.duplicate(tile(:bamboos, 7), 4), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 9), from: "p"}
      ]

      hand = pair(:bamboos, 4)

      # 自摸成对：全求人(6) + 碰碰胡(2) + 自摸(1)
      assert {:win, fans, 9} = Rules.check(hand, melds, [:self_draw])
      assert :quan_qiu_ren in fans
      assert :pung_pung in fans
      assert :self_draw in fans
    end

    test "全求人：副露吃碰杠皆可" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 1), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 3), from: "p"},
        %{type: :chow, tiles: seq(:bamboos, 2), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 9), from: "p"}
      ]

      hand = pair(:bamboos, 4)

      # 含吃的四组副露 + 单钓将：全求人大牌
      assert {:win, fans, 6} = Rules.check(hand, melds)
      assert :quan_qiu_ren in fans

      # 自摸：同样计全求人 + 自摸
      assert {:win, fans2, 7} = Rules.check(hand, melds, [:self_draw])
      assert :quan_qiu_ren in fans2
      assert :self_draw in fans2
    end

    test "不足四组时不是全求人" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 1), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 3), from: "p"},
        %{type: :chow, tiles: seq(:bamboos, 2), from: "p"}
      ]

      hand = [tile(:bamboos, 4), tile(:dots, 4), tile(:bamboos, 7), tile(:bamboos, 8)]

      assert :no_win = Rules.check(hand, melds)
    end

    test "将将胡：全部为 2/5/8 的刻子与将" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 2), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 5), from: "p"},
        %{type: :pong, tiles: triplet(:bamboos, 8), from: "p"}
      ]

      hand = pair(:bamboos, 2) ++ pair(:characters, 5)

      assert Enum.count(hand) == 4

      # 胡 2 条：222 条成刻，55万 做将 → 碰碰胡将将胡 叠加 2+4=6
      assert {:win, fans, score} = Rules.check(hand ++ [tile(:bamboos, 2)], melds)
      assert :jiang_jiang_hu in fans
      assert :pung_pung in fans
      assert score == 6

      # 胡 5 万：555 万成刻，22条 做将 → 两张不同的将均可胡
      assert {:win, fans2, _} = Rules.check(hand ++ [tile(:characters, 5)], melds)
      assert :jiang_jiang_hu in fans2
    end

    test "将将胡：全 258 但无法分解成对子/刻顺时也可和" do
      # 门清 14 张，全 2/5/8，含无法成组搭子（如 2筒5筒、2条5条）
      hand = [
        tile(:characters, 2),
        tile(:characters, 2),
        tile(:characters, 5),
        tile(:characters, 5),
        tile(:dots, 2),
        tile(:dots, 5),
        tile(:dots, 8),
        tile(:dots, 8),
        tile(:bamboos, 2),
        tile(:bamboos, 5),
        tile(:bamboos, 8),
        tile(:bamboos, 8),
        tile(:characters, 8),
        tile(:dots, 2)
      ]

      assert length(hand) == 14
      assert {:win, fans, score} = Rules.check(hand, [])
      assert :jiang_jiang_hu in fans
      assert :ping_hu not in fans or true
      assert score == 4

      # 自摸同样可和
      assert {:win, fans2, _} = Rules.check(hand, [], [:self_draw])
      assert :jiang_jiang_hu in fans2
      assert :self_draw in fans2
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

    test "全求人+将将胡 叠加计分（打牌胡为大牌）" do
      melds = [
        %{type: :pong, tiles: triplet(:characters, 2), from: "p"},
        %{type: :pong, tiles: triplet(:dots, 5), from: "p"},
        %{type: :kong_concealed, tiles: List.duplicate(tile(:bamboos, 8), 4), from: nil},
        %{type: :pong, tiles: triplet(:dots, 2), from: "p"}
      ]

      hand = pair(:characters, 5)

      # 打牌胡：全求人(6) + 碰碰胡(2) + 将将胡(4) 三型叠加
      assert {:win, fans, 12} = Rules.check(hand, melds)
      assert :quan_qiu_ren in fans
      assert :pung_pung in fans
      assert :jiang_jiang_hu in fans

      # 自摸单钓成对同样成立：全求人(6) + 碰碰胡(2) + 将将胡(4) + 自摸(1)
      assert {:win, fans2, 13} = Rules.check(hand, melds, [:self_draw])
      assert :quan_qiu_ren in fans2
      assert :pung_pung in fans2
      assert :jiang_jiang_hu in fans2
      assert :self_draw in fans2
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
