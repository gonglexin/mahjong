defmodule Mahjong.Game do
  use GenServer

  alias Mahjong.{Deck, Player}

  def new(id) do
    state = {:ok, game} = GenServer.start_link(__MODULE__, id, name: String.to_atom(id))

    :pg.join(:global, :game_servers, game)

    state
  end

  def get(id) do
    Process.whereis(String.to_atom(id))

    case Process.whereis(String.to_atom(id)) do
      nil ->
        {:error, nil}

      game ->
        {:ok, game}
    end
  end

  def get_id(game) do
    GenServer.call(game, :id)
  end

  def join(game, player) do
    GenServer.call(game, {:join, player})
  end

  def joined?(game, player) do
    GenServer.call(game, {:joined?, player})
  end

  def all_games() do
    :pg.get_members(:global, :game_servers)
  end

  def start(game) do
    GenServer.call(game, :start)
  end

  def start_by_ai(game) do
    GenServer.call(game, :start_by_ai)
  end

  def players(game) do
    GenServer.call(game, :players)
  end

  def tiles(game) do
    GenServer.call(game, :tiles)
  end

  def action(game, player, action), do: GenServer.call(game, {player, action})

  @impl true
  def init(id) do
    {:ok, %{id: id, tiles: [], players: []}}
  end

  @impl true
  def handle_call(:start, _, %{players: players} = state) when length(players) == 4 do
    tiles = Deck.shuffle()
    {four_hands, tiles} = Deck.four_hands(tiles)

    players =
      players
      |> Enum.zip(four_hands)
      |> Enum.map(fn {player, hand} ->
        %Player{player | hand: hand, in_turn?: false}
      end)

    [tile | left_tiles] = tiles

    player =
      Enum.shuffle(players)
      |> List.first()

    players =
      players
      |> Enum.map(fn p ->
        if p.id == player.id do
          Player.draw(player, tile)
        else
          p
        end
      end)

    state = %{state | tiles: left_tiles, players: players}

    {:reply, state, state}
  end

  # TODO: Add AI agent players
  @impl true
  def handle_call(:start_by_ai, _, state) do
    tiles = Deck.shuffle()
    {four_hands, tiles} = Deck.four_hands(tiles)

    players =
      Deck.positions()
      |> Enum.map(&Player.new(position: &1))
      |> Enum.zip(four_hands)
      |> Enum.map(fn {player, hand} ->
        %Player{player | hand: hand}
      end)

    [tile | left_tiles] = tiles

    player =
      Enum.shuffle(players)
      |> List.first()

    players =
      players
      |> Enum.map(fn p ->
        if p.id == player.id do
          Player.draw(player, tile)
        else
          p
        end
      end)

    state = %{state | tiles: left_tiles, players: players}
    {:reply, state, state}
  end

  @impl true
  def handle_call(:id, _, %{id: id} = state) do
    {:reply, id, state}
  end

  @impl true
  def handle_call(:tiles, _, %{tiles: tiles} = state) do
    {:reply, tiles, state}
  end

  @impl true
  def handle_call(:players, _, %{players: players} = state) do
    {:reply, players, state}
  end

  @impl true
  def handle_call({player, :draw}, _, %{tiles: tiles, players: players} = state) do
    [tile | left_tiles] = tiles

    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.draw(player, tile)
        else
          p
        end
      end)

    state = %{state | tiles: left_tiles, players: players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, {:discard, tile}}, _, %{tiles: tiles, players: players} = state) do
    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.discard(player, tile)
        else
          p
        end
      end)

    # TODO: Check players who can pong or kong, then to next position player
    next_player = next_player(players, player.position, tile)

    players =
      Enum.map(players, fn p ->
        if p.id == next_player.id do
          %{next_player | in_turn?: true}
        else
          p
        end
      end)

    state = %{state | tiles: tiles, players: players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, {:pong, tile}}, _, %{players: players} = state) do
    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.pong(player, tile)
        else
          p
        end
      end)

    state = %{state | players: players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, {:chow, {tile, with_tile}}}, _, %{players: players} = state) do
    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.chow(player, tile, with_tile)
        else
          p
        end
      end)

    state = %{state | players: players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({_player, :win}, _, %{tiles: _tiles, players: _players} = state) do
    # TODO: handle win logic
    {:reply, state, state}
  end

  @impl true
  def handle_call({:join, _player}, _, %{players: players} = state) when length(players) == 4 do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:join, player = %Player{}}, _, %{players: players} = state) do
    if player not in players do
      position = get_available_position(players)
      player = %{player | position: position}
      players = [player | players]
      state = %{state | players: players}
      {:reply, state, state}
    else
      {:reply, state, state}
    end
  end

  @impl true
  def handle_call({:joined?, player}, _, %{players: players} = state) do
    {:reply, player in players, state}
  end

  defp get_available_position(players) do
    positions = Enum.map(players, & &1.position)

    Deck.positions()
    |> Enum.reject(fn p -> p in positions end)
    |> List.first()
  end

  defp next_player(players, position, _tile) do
    players = Enum.reject(players, &(&1.position == position))

    case position do
      :east -> Enum.find(players, &(&1.position == :north))
      :north -> Enum.find(players, &(&1.position == :west))
      :west -> Enum.find(players, &(&1.position == :south))
      :south -> Enum.find(players, &(&1.position == :east))
    end
  end
end
