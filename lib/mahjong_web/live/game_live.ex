defmodule MahjongWeb.GameLive do
  use MahjongWeb, :live_view

  alias Mahjong.{Game, Player, Rules}

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
          |> assign_game(Game.state(game))

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
    state = Game.start(socket.assigns.game)

    socket =
      if state.phase == :waiting do
        put_flash(socket, :error, "Must have 4 players")
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("start_by_ai", _, socket) do
    if is_nil(socket.assigns.current_player.game_id) do
      player = Game.join(socket.assigns.game, socket.assigns.current_player)
      Game.start_by_ai(socket.assigns.game)
      {:noreply, assign(socket, :current_player, player)}
    else
      Game.start_by_ai(socket.assigns.game)
      {:noreply, socket}
    end
  end

  def handle_event("restart", _, socket) do
    Game.reset(socket.assigns.game)
    {:noreply, socket}
  end

  def handle_event("discard", %{"id" => tile_id}, socket) do
    %{current_player: player, game: game} = socket.assigns
    tile = Enum.find(player.hand, &(&1.id == tile_id))

    if player.game_id == Game.get_id(game) && tile do
      Game.action(game, player.id, {:discard, tile})
    end

    {:noreply, socket}
  end

  def handle_event("action", %{"action" => value}, socket) do
    %{current_player: player, game: game} = socket.assigns

    # 热重载/陈旧 DOM 可能送来未知动作，安全忽略
    case parse_action(value) do
      {:ok, action} -> Game.action(game, player.id, action)
      :error -> :ok
    end

    {:noreply, socket}
  end

  def handle_info({:game_update, game_state}, socket) do
    {:noreply, assign_game(socket, game_state)}
  end

  # -- 报牌窗口里可用动作的 UI 描述 ---------------------------------------------

  defp action_buttons(actions) do
    Enum.map(actions, fn
      :win ->
        %{label: "胡", value: "win", class: "btn-error"}

      :pass ->
        %{label: "过", value: "pass", class: "btn-ghost"}

      :pong ->
        %{label: "碰", value: "pong", class: "btn-warning"}

      {:kong_open} ->
        %{label: "杠", value: "kong_open", class: "btn-warning"}

      {:chow, base} ->
        %{label: "吃 #{base}-#{base + 1}-#{base + 2}", value: "chow:#{base}", class: "btn-info"}

      {:kong_concealed, t} ->
        %{
          label: "暗杠 #{t.value}",
          value: "kong_concealed:#{t.suit}:#{t.value}",
          class: "btn-warning"
        }

      {:kong_added, t} ->
        %{
          label: "加杠 #{t.value}",
          value: "kong_added:#{t.suit}:#{t.value}",
          class: "btn-warning"
        }
    end)
  end

  defp parse_action("pass"), do: {:ok, :pass}
  defp parse_action("win"), do: {:ok, :win}
  defp parse_action("pong"), do: {:ok, {:pong, nil}}
  defp parse_action("kong_open"), do: {:ok, {:kong_open}}

  defp parse_action("chow:" <> base) do
    {:ok, {:chow, String.to_integer(base)}}
  end

  defp parse_action("kong_concealed:" <> rest) do
    {:ok, {:kong_concealed, parse_tile(rest)}}
  end

  defp parse_action("kong_added:" <> rest) do
    {:ok, {:kong_added, parse_tile(rest)}}
  end

  defp parse_action(_), do: :error

  defp parse_tile(value) do
    [suit, v] = String.split(value, ":")
    %Mahjong.Tile{id: "self", suit: String.to_existing_atom(suit), value: String.to_integer(v)}
  end

  # -- 状态同步 -----------------------------------------------------------------

  defp assign_game(socket, game_state) do
    current_player = socket.assigns.current_player
    viewer = Enum.find(game_state.players, &(&1.id == current_player.id))

    current_player =
      if viewer, do: viewer, else: current_player

    turn_player = Enum.find(game_state.players, &(&1.id == game_state.turn))

    socket
    |> assign(:current_player, current_player)
    |> assign(:turn_position, turn_player && turn_player.position)
    |> assign(:tile_size, length(game_state.tiles))
    |> assign(:phase, game_state.phase)
    |> assign(:dealer, game_state.dealer)
    |> assign(:result, game_state.result)
    |> assign(:action_buttons, action_buttons(viewer_actions(game_state, viewer)))
    |> assign(:waiting_others, game_state.pending != nil)
    |> stream(:players, game_state.players, reset: true)
  end

  defp viewer_actions(_game_state, nil), do: []

  defp viewer_actions(game_state, viewer) do
    cond do
      game_state.phase != :playing ->
        []

      match?(%{eligible: _}, game_state.pending) and
          viewer.id in game_state.pending.eligible ->
        Map.get(game_state.pending[:actions] || %{}, viewer.id, []) ++ [:pass]

      game_state.turn == viewer.id ->
        Rules.self_actions(viewer.hand, viewer.open_hand)

      true ->
        []
    end
  end

  # 罗盘风位牌：当前出牌者的方位金色高亮
  defp wind_chip_class(seat, turn_position) do
    if seat == turn_position, do: "wind-char wind-char-turn", else: "wind-char"
  end

  # -- 座位视图 -----------------------------------------------------------------

  # 座位相对当前观战者：bottom 为自己；观战者以东风位视角观看
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

  # 标准麻将视图：下家在自己右手边（行牌逆时针，屏幕上 bottom→right→top→left）
  defp relative_positions(:east), do: %{left: :north, top: :west, right: :south}
  defp relative_positions(:south), do: %{left: :east, top: :north, right: :west}
  defp relative_positions(:west), do: %{left: :south, top: :east, right: :north}
  defp relative_positions(:north), do: %{left: :west, top: :south, right: :east}

  defp position_label(nil), do: "-"

  defp position_label(position) do
    %{east: "东", south: "南", west: "西", north: "北"} |> Map.get(position)
  end

  # 罗盘方位（观战者以东风位视角观看），值为座位
  defp compass_seats(current_position) do
    viewer_seat = current_position || :east
    relative = relative_positions(viewer_seat)

    %{
      top: relative.top,
      left: relative.left,
      right: relative.right,
      bottom: viewer_seat
    }
  end

  defp fan_names(fans) do
    Enum.map_join(fans, " · ", &Rules.fan_name/1)
  end
end
