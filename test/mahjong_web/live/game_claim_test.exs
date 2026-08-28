defmodule MahjongWeb.GameClaimTest do
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

  defp seq(suit, base), do: for(v <- base..(base + 2), do: tile(suit, v))

  defp pair(suit, v), do: List.duplicate(tile(suit, v), 2)

  test "出牌后可碰的玩家看到碰按钮并能完成碰", %{conn: conn} do
    # 各自先请求一次首页，让浏览器管线写入稳定的 session token（与生产一致）
    conn_a = init_test_session(conn, %{}) |> get(~p"/")
    conn_b = init_test_session(build_conn(), %{}) |> get(~p"/")
    token_a = get_session(conn_a, "_csrf_token")
    token_b = get_session(conn_b, "_csrf_token")

    id = Ecto.UUID.generate()
    {:ok, game} = Game.new(id)

    Game.join(game, Player.new(token: token_a, position: :east))
    Game.join(game, Player.new(token: token_b, position: :south))
    Game.join(game, Player.new(token: "ai-west-#{@suffix}", position: :west))
    Game.join(game, Player.new(token: "ai-north-#{@suffix}", position: :north))
    state = Game.start(game)

    dealer = Enum.find(state.players, & &1.in_turn?)
    claimed = tile(:characters, 5)

    players =
      Enum.map(state.players, fn player ->
        cond do
          player.position == :east -> %{player | hand: [claimed | filler(13)]}
          player.position == :south -> %{player | hand: pair(:characters, 5) ++ filler(11)}
          true -> %{player | hand: seq(:dots, 1) ++ seq(:bamboos, 2) ++ filler(7)}
        end
      end)

    :sys.replace_state(game, fn _ ->
      Map.merge(state, %{players: players, turn: dealer.id, tiles: filler(30)})
    end)

    {:ok, view_a, _} = live(conn_a, ~p"/game/#{id}")
    {:ok, view_b, _} = live(conn_b, ~p"/game/#{id}")

    # 甲（庄家）打出 5 万
    view_a
    |> element("[phx-value-id=\"#{claimed.id}\"]")
    |> render_click()

    # 广播异步送达乙的视图，轮询等待碰按钮出现
    html_b =
      Enum.reduce_while(1..40, nil, fn _, acc ->
        html = render(view_b)

        if html =~ "碰" do
          {:halt, html}
        else
          Process.sleep(50)
          {:cont, html}
        end
      end)

    File.write!("/tmp/html_b.html", html_b)
    assigns = :sys.get_state(view_b.pid) |> Map.get(:socket) |> Map.get(:assigns)

    IO.inspect(Map.get(assigns, :current_player) |> Map.take([:id, :position, :token]),
      label: "DBG b assigns current"
    )

    IO.inspect(
      {Map.get(assigns, :action_buttons), Map.get(assigns, :waiting_others),
       Map.get(assigns, :phase)},
      label: "DBG b assigns ui"
    )

    send(view_b.pid, {:game_update, Game.state(game)})
    Process.sleep(200)
    assigns2 = :sys.get_state(view_b.pid) |> Map.get(:socket) |> Map.get(:assigns)
    IO.inspect(Map.get(assigns2, :action_buttons), label: "DBG buttons after resend")
    pending = Game.state(game).pending

    IO.inspect(
      {pending |> Map.get(:eligible),
       Enum.find(Game.state(game).players, &(&1.position == :south)).id},
      label: "DBG eligible vs south"
    )

    File.write!("/tmp/html_b.html", html_b || "NIL")
    assert html_b && html_b =~ "碰"
    assert html_b =~ "过"

    # 乙点击碰，完成碰牌
    view_b
    |> element("button[phx-value-value=\"pong\"]")
    |> render_click()

    state = Game.state(game)
    south = Enum.find(state.players, &(&1.position == :south))
    assert [%{type: :pong}] = south.open_hand
    assert state.turn == south.id
  end
end
