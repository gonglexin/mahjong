defmodule MahjongWeb.GameLive do
  use MahjongWeb, :live_view

  alias Mahjong.{Game, Player}

  @game_player_topic "games:player"

  def mount(%{"id" => id}, session, socket) do
    if connected?(socket) do
      Mahjong.subscribe(@game_player_topic)
    end

    socket =
      case Game.get(id) do
        {:ok, game} ->
          token = Map.get(session, "_csrf_token")
          players = Game.players(game)

          current_player =
            players
            |> Enum.find(&(&1.token == token)) ||
              Player.new(token: token)

          socket
          |> assign(:game, game)
          |> assign(:current_player, current_player)
          |> stream(:tiles, Game.tiles(game))
          |> stream(:players, players)

        _ ->
          socket
          |> put_flash(:error, "Game #{id} not found!")
          |> push_navigate(to: ~p"/")
      end

    {:ok, socket}
  end

  def handle_event("join", _, socket) do
    Game.join(socket.assigns.game, socket.assigns.current_player)

    {:noreply, socket}
  end

  def handle_event("start", _, socket) do
    %{tiles: tiles, players: players} = Game.start(socket.assigns.game)

    socket =
      if length(players) == 4 do
        socket
        |> stream(:tiles, tiles)
        |> stream(:players, players)
      else
        put_flash(socket, :error, "Must have 4 players")
      end

    {:noreply, socket}
  end

  def handle_info({:player_join, {%Player{} = player, name}}, socket) do
    game = Process.whereis(name)

    socket =
      if game == socket.assigns.game do
        stream_insert(socket, :players, player)
      else
        socket
      end

    {:noreply, socket}
  end
end
