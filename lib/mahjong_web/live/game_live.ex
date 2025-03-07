defmodule MahjongWeb.GameLive do
  use MahjongWeb, :live_view

  alias Mahjong.{Game, Player}

  def mount(%{"id" => id}, session, socket) do
    if connected?(socket) do
      Mahjong.subscribe("games:#{id}")
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
    %{players: players} = Game.start(socket.assigns.game)

    socket =
      if length(players) < 4 do
        put_flash(socket, :error, "Must have 4 players")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:player_join, %Player{} = player}, socket) do
    {:noreply, stream_insert(socket, :players, player)}
  end

  def handle_info(:game_started, socket) do
    game = socket.assigns.game

    socket
    |> stream(:tiles, Game.tiles(game), reset: true)
    |> stream(:players, Game.players(game), reset: true)

    {:noreply, socket}
  end
end
