defmodule MahjongWeb.HallLive do
  use MahjongWeb, :live_view

  alias Ecto.UUID
  alias Mahjong.{Game, Player}

  def mount(_params, session, socket) do
    games = Game.all_games() || []

    token = Map.get(session, "_csrf_token")

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
      |> stream_configure(:games, dom_id: &(Game.get_id(&1)))
      |> stream(:games, games)

    {:ok, socket}
  end

  def handle_event("new_game", _, socket) do
    UUID.generate()
    |> Game.new()

    socket =
      socket
      |> stream(:games, Game.all_games(), reset: true)

    {:noreply, socket}
  end

  def handle_event("join", %{"id" => id}, socket) do
    game = :pg.get_members(:global, :game_servers) |> Enum.find(fn g -> Game.get_id(g) == id end)
    Game.join(game, socket.assigns.current_player)

    socket =
      socket
      |> push_navigate(to: ~p"/game/#{id}")

    {:noreply, socket}
  end
end
