defmodule MahjongWeb.KongAddedTest do
  use MahjongWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Phoenix.ConnTest

  alias Mahjong.{Game, Player, Tile}

  @suffix :erlang.unique_integer([:positive])

  defp tile(suit, value),
    do: %Tile{
      id: "#{suit}#{value}-#{:erlang.unique_integer([:positive])}",
      suit: suit,
      value: value
    }

  defp filler(n), do: for(i <- 1..n, do: tile(:bamboos, rem(i, 9) + 1))

  test "加杠按钮：点击后明刻升级为加杠并补牌", %{conn: conn} do
    conn_s = init_test_session(conn, %{}) |> get(~p"/")
    token_s = get_session(conn_s, "_csrf_token")

    id = Ecto.UUID.generate()
    {:ok, game} = Game.new(id)

    Game.join(game, Player.new(token: "ai-e-#{@suffix}", position: :east))
    Game.join(game, Player.new(token: token_s, position: :south))
    Game.join(game, Player.new(token: "ai-w-#{@suffix}", position: :west))
    Game.join(game, Player.new(token: "ai-n-#{@suffix}", position: :north))
    state = Game.start(game)

    pong_tile = tile(:dots, 5)
    drawn = tile(:dots, 5)

    players =
      Enum.map(state.players, fn player ->
        cond do
          player.position == :east ->
            %{player | hand: filler(14)}

          player.position == :south ->
            pong_meld = %{type: :pong, tiles: List.duplicate(pong_tile, 3), from: "east"}

            hand =
              Enum.flat_map(1..2, fn i ->
                [
                  tile(:characters, i),
                  tile(:characters, i + 3),
                  tile(:characters, i + 6)
                ]
              end) ++ [drawn]

            %{player | hand: hand, open_hand: [pong_meld], drawn: drawn}

          true ->
            %{player | hand: filler(13)}
        end
      end)

    south = Enum.find(players, &(&1.position == :south))

    :sys.replace_state(game, fn _ ->
      Map.merge(state, %{
        players: players,
        turn: south.id,
        phase: :playing,
        last_discard: nil,
        pending: nil,
        discards_made: 5,
        kong_draw?: true,
        tiles: filler(30)
      })
    end)

    {:ok, view, _} = live(conn_s, ~p"/game/#{id}")

    # 加杠按钮出现（明刻 + 手中第 4 张）
    assert view
           |> element("button[phx-value-action=\"kong_added:dots:5\"]")
           |> render_click() =~ "等待结算"

    state = Game.state(game)
    south = Enum.find(state.players, &(&1.position == :south))

    assert [%{type: :kong_added, tiles: tiles}] = south.open_hand
    assert Enum.count(tiles) == 4
    assert length(south.hand) == 7
    assert is_nil(state.pending)
    # 杠后补牌：牌墙消耗 1 张
    assert length(state.tiles) == 29
  end
end
