defmodule MahjongWeb.GameSoundTest do
  use MahjongWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Mahjong.Player
  alias Mahjong.Tile

  # 引擎在广播里直接携带动作事件（见 game.ex 的 events 与 game_events_test.exs），
  # 这里只测 GameLive 的事件 → play-sound 推送映射。

  defp fresh_view(conn) do
    id = Ecto.UUID.generate()
    {:ok, _game} = Mahjong.Game.new(id)
    {:ok, view, _html} = live(conn, ~p"/game/#{id}")
    view
  end

  defp state(players, overrides \\ []) do
    Map.merge(
      %{
        id: "game-1",
        tiles: [],
        players: players,
        phase: :playing,
        dealer: :east,
        turn: nil,
        last_discard: nil,
        pending: nil,
        discards_made: 0,
        kong_draw?: false,
        result: nil,
        events: []
      },
      Map.new(overrides)
    )
  end

  defp seated_players do
    Mahjong.Deck.positions()
    |> Enum.map(&Player.new(position: &1))
  end

  defp send_state(view, game_state, events \\ []) do
    send(view.pid, {:game_update, game_state, events})
    render(view)
  end

  describe "play-sound mapping" do
    test "discard events map to the tile's voice name", %{conn: conn} do
      view = fresh_view(conn)
      players = seated_players()

      send_state(view, state(players))

      discards = [
        {%Tile{id: "t1", suit: :characters, value: 5}, "wan5"},
        {%Tile{id: "t2", suit: :dots, value: 3}, "tong3"},
        {%Tile{id: "t3", suit: :bamboos, value: 9}, "tiao9"}
      ]

      Enum.each(discards, fn {tile, expected} ->
        send_state(view, state(players), [{:discard, tile}])
        assert_push_event(view, "play-sound", %{name: ^expected})
      end)
    end

    test "claim events map to peng, chi and gang voices", %{conn: conn} do
      view = fresh_view(conn)
      players = seated_players()

      send_state(view, state(players))

      for {event, expected} <- [{:pong, "peng"}, {:chow, "chi"}, {:kong, "gang"}] do
        send_state(view, state(players), [event])
        assert_push_event(view, "play-sound", %{name: ^expected})
      end
    end

    test "result events map to zimo, hu and liuju voices", %{conn: conn} do
      view = fresh_view(conn)
      players = seated_players()

      send_state(view, state(players))

      for {event, expected} <- [{:self_win, "zimo"}, {:discard_win, "hu"}, {:wall_empty, "liuju"}] do
        send_state(view, state(players), [event])
        assert_push_event(view, "play-sound", %{name: ^expected})
      end
    end

    test "combined events push one sound each in order", %{conn: conn} do
      view = fresh_view(conn)
      players = seated_players()

      send_state(view, state(players))

      tile = %Tile{id: "t1", suit: :characters, value: 5}
      send_state(view, state(players), [{:discard, tile}, :wall_empty])

      assert_push_event(view, "play-sound", %{name: "wan5"})
      assert_push_event(view, "play-sound", %{name: "liuju"})
    end
  end
end
