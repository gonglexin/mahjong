defmodule MahjongWeb.HallLive do
  use MahjongWeb, :live_view

  alias Ecto.UUID
  alias Mahjong.{Game, Player}

  def mount(_params, session, socket) do
    games = Game.all_games() || []

    token = Map.get(session, "_csrf_token")

    current_player =
      games
      |> Enum.flat_map(&Game.players(&1))
      |> Enum.find(&(&1.token == token)) || Player.new(token: token)

    socket =
      socket
      |> assign(:current_player, current_player)
      |> assign(:games, games)

    {:ok, socket}
  end

  def handle_event("new_game", _, socket) do
    UUID.autogenerate()
    |> Game.new()

    {:noreply, assign(socket, games: Game.all_games())}
  end

  def handle_event("join", %{"id" => id}, socket) do
    game = socket.assigns.games |> Enum.find(fn g -> Game.get_id(g) == id end)
    Game.join(game, socket.assigns.current_player)

    socket =
      socket
      |> push_navigate(to: ~p"/game/#{id}")

    {:noreply, socket}
  end
end
