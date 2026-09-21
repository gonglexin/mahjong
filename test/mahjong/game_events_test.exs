defmodule Mahjong.GameEventsTest do
  use ExUnit.Case, async: true

  alias Mahjong.{Game, Player, Tile}

  # 音效事件由引擎在动作发生时产生、随广播发出（广播元组的第三个元素）。
  # 这里用真实牌局驱动，断言每种动作都广播了对应事件。

  setup do
    id = Ecto.UUID.generate()
    {:ok, game} = Game.new(id)
    Phoenix.PubSub.subscribe(Mahjong.PubSub, "games:#{id}")

    suffix = :erlang.unique_integer([:positive])

    Game.join(game, Player.new(token: "east-#{suffix}", position: :east))
    Game.join(game, Player.new(token: "south-#{suffix}", position: :south))
    Game.join(game, Player.new(token: "west-#{suffix}", position: :west))
    Game.join(game, Player.new(token: "north-#{suffix}", position: :north))
    state = Game.start(game)

    %{game: game, state: state}
  end

  defp tile(suit, value) do
    %Tile{id: "#{suit}#{value}-#{:erlang.unique_integer([:positive])}", suit: suit, value: value}
  end

  defp filler(n), do: for(i <- 1..n, do: tile(:bamboos, rem(i, 9) + 1))

  defp seq(suit, base), do: for(v <- base..(base + 2), do: tile(suit, v))

  defp pair(suit, v), do: [tile(suit, v), tile(suit, v)]

  # 用确定性的手牌/状态覆盖开局发牌（同 game_claim_test 的做法）
  defp rig(game, hands, overrides \\ []) do
    state = Game.state(game)

    players =
      Enum.map(state.players, fn player ->
        %{player | hand: Map.get(hands, player.position, player.hand)}
      end)

    :sys.replace_state(game, fn _ ->
      state |> Map.merge(Map.new(overrides)) |> Map.put(:players, players)
    end)
  end

  defp dealer(state), do: Enum.find(state.players, & &1.in_turn?)

  defp claimless_hands do
    %{
      west: seq(:dots, 1) ++ seq(:bamboos, 2) ++ filler(7),
      north: seq(:dots, 4) ++ seq(:bamboos, 5) ++ filler(7)
    }
  end

  test "出牌广播携带 discard 事件与牌面", %{game: game, state: state} do
    dealer = dealer(state)
    hand = [winning = tile(:characters, 5) | filler(13)]

    rig(game, Map.merge(claimless_hands(), %{dealer.position => hand, south: filler(13)}),
      turn: dealer.id
    )

    Game.action(game, dealer.id, {:discard, winning})

    assert_receive {:game_update, _, [{:discard, ev}]}, 500
    assert Tile.same?(ev, winning)
  end

  test "牌墙打空时同一广播携带 wall_empty 事件", %{game: game, state: state} do
    dealer = dealer(state)
    hand = [winning = tile(:characters, 5) | filler(13)]

    rig(game, Map.merge(claimless_hands(), %{dealer.position => hand, south: filler(13)}),
      turn: dealer.id,
      tiles: []
    )

    Game.action(game, dealer.id, {:discard, winning})

    assert_receive {:game_update, _, [{:discard, _}, :wall_empty]}, 500
  end

  test "碰结算广播携带 pong 事件", %{game: game, state: state} do
    dealer = dealer(state)
    south = Enum.find(state.players, &(&1.position == :south))
    claimed = tile(:characters, 5)

    rig(
      game,
      Map.merge(claimless_hands(), %{
        dealer.position => [claimed | filler(13)],
        south: pair(:characters, 5) ++ filler(11)
      }),
      turn: dealer.id
    )

    Game.action(game, dealer.id, {:discard, claimed})
    assert_receive {:game_update, _, [{:discard, _}]}, 500

    Game.action(game, south.id, {:pong, nil})
    assert_receive {:game_update, _, [:pong]}, 500
  end

  test "自摸广播携带 self_win 事件", %{game: game, state: state} do
    dealer = dealer(state)

    hand =
      seq(:characters, 1) ++
        seq(:characters, 4) ++
        seq(:characters, 7) ++
        seq(:dots, 2) ++ pair(:characters, 5)

    rig(game, %{dealer.position => hand}, turn: dealer.id)

    Game.action(game, dealer.id, :win)

    assert_receive {:game_update, _, [:self_win]}, 500
  end

  test "暗杠广播携带 kong 事件", %{game: game, state: state} do
    dealer = dealer(state)
    kong_tile = tile(:bamboos, 3)
    hand = List.duplicate(kong_tile, 4) ++ for(i <- 1..9, do: tile(:dots, rem(i, 9) + 1))
    rig(game, %{dealer.position => hand}, turn: dealer.id, tiles: filler(10))

    Game.action(game, dealer.id, {:kong_concealed, kong_tile})

    assert_receive {:game_update, _, [:kong]}, 500
  end

  test "重开局广播不携带任何事件", %{game: game} do
    Game.reset(game)
    assert_receive {:game_update, _, []}, 500
  end
end
