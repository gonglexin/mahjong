defmodule Mahjong.GameTest do
  # 全局游戏进程注册表：与其它 LiveView 测试互斥执行，避免渲染冲突
  use ExUnit.Case, async: false

  alias Mahjong.{Game, Player, Tile}

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

  defp setup_game do
    id = Ecto.UUID.generate()
    {:ok, game} = Game.new(id)

    players =
      for pos <- [:east, :south, :west, :north] do
        Player.new(token: "t-#{pos}-#{@suffix}", position: pos)
      end

    for p <- players, do: Game.join(game, p)
    %{game: game, players: players, id: id}
  end

  defp replace_state(game, state), do: :sys.replace_state(game, fn _ -> state end)

  defp base_state(%{game: game, players: players}, overrides) do
    Map.merge(
      %{
        id: game |> Mahjong.Game.get_id(),
        tiles: filler(30),
        players: players,
        phase: :playing,
        dealer: :east,
        turn: nil,
        last_discard: nil,
        pending: nil,
        discards_made: 1,
        kong_draw?: false,
        result: nil,
        ai_timer: nil
      },
      Map.new(overrides)
    )
  end

  defp hand_for(players, position, hand) do
    Enum.map(players, fn player ->
      if player.position == position, do: %{player | hand: hand}, else: player
    end)
  end

  test "开局发牌：庄家 14 张并先手" do
    %{game: game} = setup_game()
    state = Game.start(game)

    assert state.phase == :playing
    assert Enum.map(state.players, &length(&1.hand)) |> Enum.sort() == [13, 13, 13, 14]
    assert length(state.tiles) == 55

    dealer = Enum.find(state.players, &(&1.position == :east))
    assert state.turn == dealer.id
    assert length(dealer.hand) == 14
  end

  test "出牌后逆时针轮到下一家摸牌" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    # 其余家手牌与 5 万无关联，确保无人报牌
    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(
        :south,
        seq(:dots, 1) ++
          seq(:bamboos, 2) ++
          seq(:characters, 7) ++
          [
            tile(:bamboos, 9),
            tile(:dots, 8),
            tile(:characters, 4),
            tile(:dots, 6)
          ]
      )
      |> hand_for(
        :west,
        seq(:characters, 1) ++
          seq(:dots, 2) ++
          seq(:bamboos, 3) ++
          [
            tile(:dots, 8),
            tile(:bamboos, 6),
            tile(:characters, 4),
            tile(:dots, 6)
          ]
      )
      |> hand_for(
        :north,
        seq(:dots, 1) ++
          seq(:characters, 2) ++
          seq(:bamboos, 4) ++
          [
            tile(:dots, 9),
            tile(:characters, 4),
            tile(:bamboos, 6),
            tile(:bamboos, 9)
          ]
      )

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})

    south = Enum.find(state.players, &(&1.position == :south))
    assert state.turn == south.id
    assert length(south.hand) == 14
    assert length(state.tiles) == 29
  end

  test "碰：拿走弃牌组成刻子且不摸牌" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, pair(:characters, 5) ++ filler(11))
      |> hand_for(
        :west,
        seq(:characters, 1) ++ seq(:dots, 2) ++ seq(:bamboos, 3) ++ [tile(:dots, 8)]
      )
      |> hand_for(
        :north,
        seq(:dots, 1) ++ seq(:characters, 2) ++ seq(:bamboos, 4) ++ [tile(:dots, 9)]
      )

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    # 东家打出 5 万，南家碰
    state = Game.action(game, dealer.id, {:discard, claimed})
    south = Enum.find(state.players, &(&1.position == :south))
    state = Game.action(game, south.id, {:pong, nil})

    south = Enum.find(state.players, &(&1.position == :south))
    east = Enum.find(state.players, &(&1.position == :east))

    assert state.turn == south.id
    assert [%{type: :pong} = meld] = south.open_hand
    assert Tile.same?(hd(meld.tiles), claimed)
    assert length(south.hand) == 11
    assert east.discards == []
    # 碰后不摸牌，牌墙数量不变
    assert length(state.tiles) == 30
  end

  test "AI 报牌决策：可碰则碰，碰后轮到其出牌" do
    id = Ecto.UUID.generate()
    {:ok, game} = Game.new(id)

    players =
      for {pos, persona} <- [
            {:east, nil},
            {:south, :rational},
            {:west, :casual},
            {:north, :greedy}
          ] do
        Player.new(token: "ai-#{pos}-#{@suffix}", position: pos, persona: persona)
      end

    for p <- players, do: Game.join(game, p)
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, pair(:characters, 5) ++ filler(11))
      |> hand_for(
        :west,
        seq(:characters, 1) ++ seq(:dots, 2) ++ seq(:bamboos, 3) ++ [tile(:dots, 8)]
      )
      |> hand_for(
        :north,
        seq(:dots, 1) ++ seq(:characters, 2) ++ seq(:bamboos, 4) ++ [tile(:dots, 9)]
      )

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    # 东家打出 5 万，报牌窗口开启
    state = Game.action(game, dealer.id, {:discard, claimed})
    assert state.pending.phase == :take

    # 触发 AI 报牌决策（南家 AI 性格 :rational，可碰且改善向听 → 碰）
    send(game, {:ai_claims, state.pending.gen})
    state = Game.state(game)
    IO.inspect(state.pending && state.pending.phase, label: "DBG phase after ai_claims")
    IO.inspect(state.pending && state.pending.actions, label: "DBG actions")
    south = Enum.find(state.players, &(&1.position == :south))

    assert [%{type: :pong}] = south.open_hand
    assert state.turn == south.id
    assert length(south.hand) == 11
    assert is_nil(state.pending)
  end

  test "吃牌仅限下家：下家动作含吃，上家不含" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:north, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:west, filler(13))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})

    south = Enum.find(state.players, &(&1.position == :south))

    # 下家（南）只有 3-4-5 一种吃法；上家（北）同牌型但无吃权
    assert state.pending.actions[south.id] == [{:chow, 3}]

    refute Map.has_key?(
             state.pending.actions,
             Enum.find(state.players, &(&1.position == :north)).id
           )
  end

  test "对家可碰未表态时，下家不见吃；对家过碰后下家立即出现吃" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:west, pair(:characters, 5) ++ filler(11))
      |> hand_for(:north, filler(13))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    # 庄家打出 5 万：对家（西）可碰 → 主窗口只有西；下家（南）的吃被延迟
    state = Game.action(game, dealer.id, {:discard, claimed})

    south = Enum.find(state.players, &(&1.position == :south))
    west = Enum.find(state.players, &(&1.position == :west))

    assert state.pending.eligible == [west.id]
    refute south.id in state.pending.eligible

    # 对家放弃碰 → 延迟窗口激活，下家出现吃
    state = Game.action(game, west.id, :pass)

    assert state.pending.eligible == [south.id]
    assert state.pending.actions[south.id] == [{:chow, 3}]

    # 下家吃牌，完成流程
    state = Game.action(game, south.id, {:chow, 3})

    south = Enum.find(state.players, &(&1.position == :south))
    assert [%{type: :chow, tiles: tiles}] = south.open_hand
    assert Enum.map(tiles, & &1.value) == [3, 4, 5]
    assert state.turn == south.id
  end

  test "对家与上家均超时放弃后，延迟吃窗口激活" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:west, pair(:characters, 5) ++ filler(11))
      |> hand_for(:north, pair(:characters, 5) ++ filler(11))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})

    # 主窗口包含对家与上家
    west = Enum.find(state.players, &(&1.position == :west))
    north = Enum.find(state.players, &(&1.position == :north))
    assert Enum.sort(state.pending.eligible) == Enum.sort([west.id, north.id])

    # 超时（等同全部放弃）→ 延迟吃窗口激活
    send(game, :claim_timeout)
    state = Game.state(game)

    south = Enum.find(state.players, &(&1.position == :south))
    assert state.pending.eligible == [south.id]
    assert state.pending.actions[south.id] == [{:chow, 3}]
  end

  test "上家绕过界面直接吃被拒绝" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:north, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:west, filler(13))
      |> hand_for(:south, filler(13))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})

    north = Enum.find(state.players, &(&1.position == :north))
    assert {:error, :invalid_claim} = Game.action(game, north.id, {:chow, 3})
  end

  test "下家吃牌后轮到其出牌" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:west, filler(13))
      |> hand_for(:north, filler(13))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})
    south = Enum.find(state.players, &(&1.position == :south))
    state = Game.action(game, south.id, {:chow, 3})

    south = Enum.find(state.players, &(&1.position == :south))
    east = Enum.find(state.players, &(&1.position == :east))

    assert state.turn == south.id
    assert [%{type: :chow, tiles: tiles}] = south.open_hand
    assert Enum.map(tiles, & &1.value) == [3, 4, 5]
    assert length(south.hand) == 11
    assert east.discards == []
    assert length(state.tiles) == 30
  end

  test "点炮胡：报牌窗口内胡牌结算" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    winning_tile = tile(:dots, 2)

    players =
      hand_for(players, :east, [winning_tile | filler(13)])
      |> hand_for(
        :south,
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++ [tile(:dots, 2), tile(:dots, 2), tile(:dots, 3), tile(:dots, 4)]
      )

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    # 庄家打出 2 筒
    state = Game.action(game, dealer.id, {:discard, winning_tile})

    south = Enum.find(state.players, &(&1.position == :south))
    state = Game.action(game, south.id, :win)

    assert state.phase == :over
    assert state.result.type == :discard_win
    assert state.result.winner_id == south.id
    assert :ping_hu in state.result.fans
  end

  test "胡 > 碰：有人可胡时碰被拒绝" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:dots, 2)

    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(
        :south,
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++ [tile(:dots, 2), tile(:dots, 2), tile(:dots, 3), tile(:dots, 4)]
      )
      |> hand_for(:west, pair(:dots, 2) ++ filler(11))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    # 庄家打出 2 筒，西家碰被拒（南家可胡）
    state = Game.action(game, dealer.id, {:discard, claimed})
    west = Enum.find(state.players, &(&1.position == :west))

    assert {:error, :invalid_claim} = Game.action(game, west.id, {:pong, nil})

    # 南家胡
    south = Enum.find(state.players, &(&1.position == :south))
    state = Game.action(game, south.id, :win)
    assert state.phase == :over
    assert state.result.winner_id == south.id
  end

  test "自摸胡：含杠上开花番" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    drawn = tile(:bamboos, 9)

    hand =
      seq(:characters, 1) ++
        seq(:characters, 4) ++
        seq(:dots, 3) ++
        [tile(:bamboos, 7), tile(:bamboos, 8)] ++ pair(:dots, 2) ++ [drawn]

    players = hand_for(players, :east, hand)

    state =
      base_state(%{game: game, players: players},
        turn: dealer.id,
        kong_draw?: true
      )

    replace_state(game, state)

    state = Game.action(game, dealer.id, :win)

    assert state.phase == :over
    assert state.result.type == :self_win
    assert :kong_blossom in state.result.fans
    assert :self_draw in state.result.fans
    assert state.result.score == length(state.result.fans)
  end

  test "流局：牌墙摸空" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    players = hand_for(players, :east, filler(14))
    state = base_state(%{game: game, players: players}, turn: dealer.id, tiles: [])
    replace_state(game, state)

    east_hand = Enum.find(players, &(&1.position == :east)).hand
    state = Game.action(game, dealer.id, {:discard, hd(east_hand)})

    assert state.phase == :over
    assert state.result.type == :wall_empty
  end

  test "可胡又可碰的玩家：先问胡，放弃后再问碰" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:dots, 2)

    # 南家：123/456/789万 + 22筒 —— 既能胡又能碰；西家：仅能碰
    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(
        :south,
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++ [tile(:dots, 2), tile(:dots, 2), tile(:dots, 3), tile(:dots, 4)]
      )
      |> hand_for(:west, pair(:dots, 2) ++ filler(11))

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})

    south = Enum.find(state.players, &(&1.position == :south))
    west = Enum.find(state.players, &(&1.position == :west))

    # 第一阶段：只问胡
    assert state.pending.phase == :win
    assert state.pending.eligible == [south.id]
    assert state.pending.actions[south.id] == [:win]
    refute west.id in state.pending.eligible

    # 南家放弃胡 → 第二阶段：碰
    state = Game.action(game, south.id, :pass)

    assert state.pending.phase == :take
    assert Enum.sort(state.pending.eligible) == Enum.sort([south.id, west.id])
    assert :pong in state.pending.actions[south.id]
    assert :pong in state.pending.actions[west.id]

    # 西家碰成立
    state = Game.action(game, west.id, {:pong, nil})

    west = Enum.find(state.players, &(&1.position == :west))
    assert [%{type: :pong}] = west.open_hand
    assert state.turn == west.id
  end

  test "胡→碰→吃 全链路：每一阶段都要等待放弃" do
    %{game: game, players: players} = setup_game()
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    # 北家可胡 5 万（万子牌型 333 + 55 将）；西家可碰；南家可吃
    players =
      hand_for(players, :east, [claimed | filler(13)])
      |> hand_for(:south, [tile(:characters, 3), tile(:characters, 4)] ++ filler(11))
      |> hand_for(:west, pair(:characters, 5) ++ filler(11))
      |> hand_for(
        :north,
        seq(:characters, 1) ++
          seq(:characters, 4) ++
          seq(:characters, 7) ++ seq(:dots, 7) ++ [tile(:characters, 5)]
      )

    state = base_state(%{game: game, players: players}, turn: dealer.id)
    replace_state(game, state)

    state = Game.action(game, dealer.id, {:discard, claimed})

    south = Enum.find(state.players, &(&1.position == :south))
    west = Enum.find(state.players, &(&1.position == :west))
    north = Enum.find(state.players, &(&1.position == :north))

    # 阶段一：胡
    assert state.pending.phase == :win
    assert state.pending.eligible == [north.id]

    # 北家放弃胡 → 阶段二：碰
    state = Game.action(game, north.id, :pass)
    assert state.pending.phase == :take

    # 西家和北家手里都有 5 万对子，均可碰
    assert Enum.sort(state.pending.eligible) == Enum.sort([west.id, north.id])
    assert :pong in state.pending.actions[west.id]
    assert :pong in state.pending.actions[north.id]

    # 西家、北家都放弃碰 → 阶段三：吃
    state = Game.action(game, west.id, :pass)
    assert state.pending.phase == :take

    state = Game.action(game, north.id, :pass)
    assert state.pending.phase == :chow
    assert state.pending.eligible == [south.id]

    # 南家吃
    state = Game.action(game, south.id, {:chow, 3})
    south = Enum.find(state.players, &(&1.position == :south))
    assert [%{type: :chow}] = south.open_hand
    assert state.turn == south.id
  end
end
