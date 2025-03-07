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

          all_game_players =
            Game.all_games()
            |> Enum.flat_map(&Game.players(&1))

          current_player =
            all_game_players
            |> Enum.find(&(&1.token == token)) ||
              Player.new(token: token)

          socket
          |> assign(:game, game)
          |> assign(:current_player, current_player)
          |> stream(:tiles, Game.tiles(game))
          |> stream(:players, Game.players(game))

        _ ->
          socket
          |> put_flash(:error, "Game #{id} not found!")
          |> push_navigate(to: ~p"/")
      end

    {:ok, socket}
  end

  def handle_event("join", _, socket) do
    if is_nil(socket.assigns.current_player.game_id) do
      player = Game.join(socket.assigns.game, socket.assigns.current_player)
      {:noreply, assign(socket, :current_player, player)}
    else
      {:noreply, put_flash(socket, :error, "You are already in a game!")}
    end
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

  def handle_event("discard", %{"id" => tile_id}, socket) do
    tile = Enum.find(socket.assigns.current_player.hand, &(&1.id == tile_id))
    Game.action(socket.assigns.game, socket.assigns.current_player, {:discard, tile})
    {:noreply, socket}
  end

  def handle_info({:player_join, %Player{} = player}, socket) do
    {:noreply, stream_insert(socket, :players, player)}
  end

  def handle_info({:game_started, %{tiles: tiles, players: players}}, socket) do
    socket =
      socket
      |> stream(:tiles, tiles, reset: true)
      |> stream(:players, players, reset: true)

    {:noreply, socket}
  end

  def handle_info({:player_discard, {player, _tile}}, socket) do
    require Logger
    Logger.info(inspect(player.discards))

    socket =
      socket
      |> stream_insert(:players, player)

    {:noreply, socket}
  end
end
