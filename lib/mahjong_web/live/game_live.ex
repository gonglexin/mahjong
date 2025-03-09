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
    Game.action(socket.assigns.game, socket.assigns.current_player.id, {:discard, tile})
    {:noreply, socket}
  end

  def handle_info({:player_join, %Player{} = player}, socket) do
    {:noreply, stream_insert(socket, :players, player)}
  end

  def handle_info({:game_started, %{tiles: tiles, players: players}}, socket) do
    # Update current palyer hand
    current_player =
      Enum.find(players, fn player -> player.id == socket.assigns.current_player.id end)

    socket =
      socket
      |> assign(current_player: current_player)
      |> stream(:tiles, tiles, reset: true)
      |> stream(:players, players, reset: true)

    {:noreply, socket}
  end

  def handle_info({:player_discard, {player, next_player, _tile}}, socket) do
    current_player =
      if socket.assigns.current_player.id == player.id,
        do: player,
        else: socket.assigns.current_player

    socket =
      socket
      |> assign(:current_player, current_player)
      |> stream_insert(:players, player)
      |> stream_insert(:players, next_player)

    {:noreply, socket}
  end

  defp get_player_class(player, current_player) do
    relative_positions = get_relative_positions(current_player.position)

    cond do
      player.position == current_player.position -> "player-bottom"
      player.position == relative_positions.left -> "player-left"
      player.position == relative_positions.top -> "player-top"
      player.position == relative_positions.right -> "player-right"
    end
  end

  defp get_player_position(player, current_player) do
    relative_positions = get_relative_positions(current_player.position)

    cond do
      player.position == current_player.position -> "bottom"
      player.position == relative_positions.left -> "left"
      player.position == relative_positions.top -> "top"
      player.position == relative_positions.right -> "right"
    end
  end

  defp get_relative_positions(current_position) do
    case current_position do
      :east -> %{left: :south, top: :west, right: :north}
      :south -> %{left: :west, top: :north, right: :east}
      :west -> %{left: :north, top: :east, right: :south}
      :north -> %{left: :east, top: :south, right: :west}
    end
  end

  defp get_direction_markers(current_position) do
    case current_position do
      :east -> %{top: "西", left: "南", right: "北", bottom: "东"}
      :south -> %{top: "北", left: "西", right: "东", bottom: "南"}
      :west -> %{top: "东", left: "北", right: "南", bottom: "西"}
      :north -> %{top: "南", left: "东", right: "西", bottom: "北"}
    end
  end
end
