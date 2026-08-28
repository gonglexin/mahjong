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
          |> assign(:tile_size, length(Game.tiles(game)))
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

  def handle_event("start_by_ai", _, socket) do
    if is_nil(socket.assigns.current_player.game_id) do
      player = Game.join(socket.assigns.game, socket.assigns.current_player)
      socket = assign(socket, :current_player, player)
      Game.start_by_ai(socket.assigns.game)
      {:noreply, socket}
    else
      Game.start_by_ai(socket.assigns.game)
      {:noreply, socket}
    end
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
    # Seated viewers get their dealt player; spectators keep the unseated one
    current_player =
      Enum.find(players, fn player -> player.id == socket.assigns.current_player.id end) ||
        socket.assigns.current_player

    socket =
      socket
      |> assign(:current_player, current_player)
      |> assign(:tile_size, length(tiles))
      |> stream(:players, players, reset: true)

    {:noreply, socket}
  end

  # Seats relative to the current viewer: bottom is always "me" when seated.
  # Spectators view from the default east seat.
  defp seat_position(player, current_player) do
    viewer_seat = current_player.position || :east
    relative = relative_positions(viewer_seat)

    cond do
      player.id == current_player.id or player.position == viewer_seat -> "bottom"
      player.position == relative.left -> "left"
      player.position == relative.top -> "top"
      player.position == relative.right -> "right"
      true -> "waiting"
    end
  end

  defp seat_class(player, current_player) do
    "seat-" <> seat_position(player, current_player)
  end

  defp relative_positions(current_position) do
    case current_position do
      :east -> %{left: :south, top: :west, right: :north}
      :south -> %{left: :west, top: :north, right: :east}
      :west -> %{left: :north, top: :east, right: :south}
      :north -> %{left: :east, top: :south, right: :west}
    end
  end

  defp position_label(nil), do: "-"

  defp position_label(position) do
    %{east: "东", south: "南", west: "西", north: "北"} |> Map.get(position)
  end

  # Wind labels around the center marker, from the viewer's perspective
  defp get_direction_markers(current_position) do
    case current_position do
      :east -> %{top: "西", left: "南", right: "北", bottom: "东"}
      :south -> %{top: "北", left: "西", right: "东", bottom: "南"}
      :west -> %{top: "东", left: "北", right: "南", bottom: "西"}
      :north -> %{top: "南", left: "东", right: "西", bottom: "北"}
      nil -> %{top: "北", left: "西", right: "东", bottom: "南"}
    end
  end
end
