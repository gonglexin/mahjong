defmodule MahjongWeb.GameLiveTest do
  use MahjongWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Mahjong.{Game, Player}

  describe "mount/3" do
    test "renders game when it exists", %{conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, _game} = Game.new(id)
      {:ok, _view, html} = live(conn, ~p"/game/#{id}")

      assert html =~ "东"
    end

    test "redirects when game does not exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/game/invalid-id")
    end
  end

  describe "handle_event/3" do
    @tag :skip
    test "join - adds player to game", %{conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, _game} = Game.new(id)
      {:ok, view, _html} = live(conn, ~p"/game/#{id}")

      assert view
             |> element("button", "Join")
             |> render_click() =~ "Joined successfully"
    end

    test "start - fails with less than 4 players", %{conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, _game} = Game.new(id)
      {:ok, view, _html} = live(conn, ~p"/game/#{id}")

      assert view
             |> element("button[phx-click=\"start\"]")
             |> render_click() =~ "Must have 4 players"
    end

    test "discard - renders empty board for unseated player", %{conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, _game} = Game.new(id)
      {:ok, view, _html} = live(conn, ~p"/game/#{id}")

      # No players seated yet: board renders with counter but no seats
      html = view |> element("#game-board") |> render()
      assert html =~ "余牌"
      refute html =~ "seat-bottom"
    end
  end

  describe "handle_info/2" do
    test ":player_join renders unseated player without crashing", %{conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, _game} = Game.new(id)
      {:ok, view, _html} = live(conn, ~p"/game/#{id}")

      player = Player.new(token: "token-1")
      send(view.pid, {:player_join, player})

      assert render(view) =~ "seat-waiting"
      assert render(view) =~ "token-1"
    end

    test ":game_started - updates players and tile count", %{conn: conn} do
      id = Ecto.UUID.generate()
      {:ok, _game} = Game.new(id)
      {:ok, view, _html} = live(conn, ~p"/game/#{id}")

      {hand, _} = Mahjong.Deck.new_hand(Mahjong.Deck.shuffle())

      players =
        Mahjong.Deck.positions()
        |> Enum.zip(List.duplicate(hand, 4))
        |> Enum.map(fn {position, hand} -> %{Player.new(position: position) | hand: hand} end)

      send(view.pid, {:game_started, %{tiles: [], players: players}})

      html = render(view)
      assert html =~ "seat-bottom"
      assert html =~ "seat-top"
      assert html =~ "seat-left"
      assert html =~ "seat-right"
      assert html =~ "余牌"
    end
  end
end
