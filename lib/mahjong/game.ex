defmodule Mahjong.Game do
  use GenServer

  alias Mahjong.{Deck, Player}

  def join(game, player) do
    GenServer.call(game, {:join, player})
  end

  def start(game) do
    GenServer.call(game, :start)
  end

  def start_by_ai(game) do
    GenServer.call(game, :start_by_ai)
  end

  def left_tiles(game) do
    GenServer.call(game, :left_tiles)
  end

  def start_link(nil) do
    GenServer.start(__MODULE__, nil)
  end

  def action(game, player, action), do: GenServer.call(game, {player, action})

  @impl true
  def init(_init_arg) do
    {:ok, {Deck.shuffle(), []}}
  end

  @impl true
  def handle_call(:start, _, {tiles, players}) when length(players) == 4 do
    {four_hands, tiles} = Deck.four_hands(tiles)

    players =
      players
      |> Enum.zip(four_hands)
      |> Enum.map(fn {player, hand} ->
        %{player | hand: hand}
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

    state = {left_tiles, players}

    {:reply, state, state}
  end

  # TODO: Add AI agent players
  @impl true
  def handle_call(:start_by_ai, _, {tiles, _players}) do
    {four_hands, tiles} = Deck.four_hands(tiles)

    players =
      Deck.positions()
      |> Enum.map(&Player.new(position: &1))
      |> Enum.zip(four_hands)
      |> Enum.map(fn {player, hand} ->
        %{player | hand: hand}
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

    state = {left_tiles, players}
    {:reply, state, state}
  end

  @impl true
  def handle_call(:left_tiles, _, {tiles, _players} = state) do
    {:reply, tiles, state}
  end

  @impl true
  def handle_call({player, :draw}, _, {tiles, players}) do
    [tile | left_tiles] = tiles

    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.draw(player, tile)
        else
          p
        end
      end)

    state = {left_tiles, players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, {:discard, tile}}, _, {tiles, players}) do
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

    state = {tiles, players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, {:pong, tile}}, _, {tiles, players}) do
    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.pong(player, tile)
        else
          p
        end
      end)

    state = {tiles, players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, {:chow, {tile, with_tile}}}, _, {tiles, players}) do
    players =
      Enum.map(players, fn p ->
        if p.id == player.id do
          Player.chow(player, tile, with_tile)
        else
          p
        end
      end)

    state = {tiles, players}
    {:reply, state, state}
  end

  @impl true
  def handle_call({player, :win}, _, {tiles, players} = state) do
    # TODO: handle win logic
    {:reply, state, state}
  end

  @impl true
  def handle_call({:join, _player}, _, {_tiles, players} = state) when length(players) == 4 do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:join, player = %Player{}}, _, {tiles, players}) do
    position = get_available_position(players)
    player = %{player | position: position}
    players = [player | players]
    state = {tiles, players}
    {:reply, state, state}
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
