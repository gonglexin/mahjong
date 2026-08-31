defmodule Mahjong.PlayerTest do
  use ExUnit.Case, async: true

  alias Mahjong.{Player, Tile}

  test "出牌按 id 精确移除：手牌持有同面值两张时，被弃的牌不再留在手牌" do
    a = %Tile{id: "a", suit: :dots, value: 6}
    b = %Tile{id: "b", suit: :dots, value: 6}

    filler =
      for i <- 1..11, do: %Tile{id: "f#{i}", suit: :characters, value: rem(i, 9) + 1}

    player = Player.new(token: "t")
    player = %{player | hand: [a, b] ++ filler}

    # 摸到同样的牌后打出其中一张（点击 b）：b 离开手牌进入弃牌堆，a 保留
    player = Player.discard(player, b)

    assert [%Tile{id: "b"}] = player.discards
    assert Enum.any?(player.hand, &(&1.id == "a"))
    refute Enum.any?(player.hand, &(&1.id == "b"))

    # 手牌 + 弃牌堆中不应出现重复 id（否则 DOM 产生重复 id）
    all = player.hand ++ player.discards
    assert Enum.uniq_by(all, & &1.id) |> length() == length(all)
  end
end
