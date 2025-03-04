defmodule MahjongWeb.GameLive do
  use MahjongWeb, :live_view

  alias Mahjong.{Game, Player}

  require IEx
  require Logger

  def mount(%{"id" => id}, session, socket) do
    {:ok, game} = Game.get(id)

    token = Map.get(session, "_csrf_token")
    players = Game.players(game)

    current_player =
      players
      |> Enum.find(&(&1.token == token)) ||
        Player.new(token: token)

    socket =
      socket
      |> assign(:game, game)
      |> assign(:current_player, current_player)
      |> assign(:tiles, Game.tiles(game))
      |> assign(:players, players)

    {:ok, socket}
  end

  def handle_event("join", _, socket) when length(socket.assigns.players) == 4 do
    {:noreply, socket}
  end

  def handle_event("join", _, socket) do
    # TODO: Intergate with Accounts

    # player =
    #   Enum.find(socket.assigns.players, fn p -> p.token == token end) ||
    #     Player.new(token: token)

    # %{tiles: tiles, players: players} = Game.join(socket.assigns.game, player)

    %{tiles: tiles, players: players} =
      Game.join(socket.assigns.game, socket.assigns.current_player)

    current_player =
      Enum.find(players, fn p -> p.token == socket.assigns.current_player.token end)

    socket =
      socket
      |> assign(:tiles, tiles)
      |> assign(:current_player, current_player)
      |> assign(:players, players)

    {:noreply, socket}
  end

  def handle_event("start", _, socket) do
    %{tiles: tiles, players: players} = Game.start(socket.assigns.game)

    socket =
      socket
      |> assign(:tiles, tiles)
      |> assign(:players, players)

    {:noreply, socket}
  end
end
