defmodule MahjongWeb.HallLive do
  use MahjongWeb, :live_view

  alias Ecto.UUID
  alias Mahjong.{Game, Player}

  @game_new_topic "games:new"
  @game_player_topic "games:player"

  def mount(_params, session, socket) do
    games =
      case Game.all_games() do
        [] ->
          {:ok, game} = Game.new(UUID.generate())
          [game]

        games ->
          games
      end

    token = Map.get(session, "_csrf_token")

    if connected?(socket) do
      [@game_new_topic, @game_player_topic]
      |> Enum.map(&Mahjong.subscribe/1)
    end

    # When the player fist access site and hasn't join any
    # game, which means player doesn't exist in any existed game
    # players. When you refresh the page it'll generate a new player who's
    # token is same but id is different as the origianl one
    current_player =
      games
      |> Enum.flat_map(&Game.players(&1))
      |> Enum.find(&(&1.token == token)) || Player.new(token: token)

    socket =
      socket
      |> assign(:current_player, current_player)
      |> stream_configure(:games, dom_id: &Game.get_id(&1))
      |> stream(:games, games)

    {:ok, socket}
  end

  def handle_event("new_game", _, socket) do
    UUID.generate()
    |> Game.new()

    {:noreply, socket}
  end

  def handle_event("join", %{"id" => id}, socket) do
    game = Game.all_games() |> Enum.find(fn game -> Game.get_id(game) == id end)
    Game.join(game, socket.assigns.current_player)

    socket =
      socket
      |> push_navigate(to: ~p"/game/#{id}")

    {:noreply, socket}
  end

  def handle_info({:new_game, name}, socket) do
    game = Process.whereis(name)

    socket =
      socket
      |> stream_insert(:games, game, at: 0)

    {:noreply, socket}
  end

  # BUG: The game duplicate in a new row
  def handle_info({:player_join, {%Player{} = _player, name}}, socket) do
    game = Process.whereis(name)

    socket =
      socket
      |> stream_insert(:games, game)

    {:noreply, socket}
  end
end
