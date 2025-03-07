defmodule Mahjong.Player do
  defstruct [:id, :token, :position, :hand, :open_hand, :discards, :in_turn?, :game_id]

  alias Ecto.UUID

  def new(attrs \\ %{}) do
    %__MODULE__{
      id: UUID.generate(),
      token: attrs[:token],
      position: attrs[:position],
      hand: attrs[:hand] || [],
      open_hand: [],
      discards: [],
      in_turn?: false,
      game_id: nil
    }
  end

  # Put tile at the end of hand
  def draw(player, tile) do
    %{player | hand: player.hand ++ [tile], in_turn?: true}
  end

  # TODO:
  # 1. After discard, we need to resort tiles in hand
  # 2. Construct discards list in a better way
  def discard(player, tile) do
    %{
      player
      | hand: List.delete(player.hand, tile),
        discards: player.discards ++ [tile],
        in_turn?: false
    }
  end

  # TODO: get the right tiles to delete
  def pong(player, tile) do
    # Remove two matching tiles from hand
    hand = List.delete(player.hand, tile)
    hand = List.delete(hand, tile)

    # Add the pong set to open hand
    open_hand = [{tile, tile, tile} | player.open_hand]

    %{player | hand: hand, open_hand: open_hand}
  end

  @doc """
  `with_tile` should be the least value in hand which used to chow
  """
  def chow(player, tile, with_tile) do
    # Ensure tiles are of the same suit
    if tile.suit != with_tile.suit do
      raise ArgumentError, "Chow can only be made with tiles of the same suit"
    end

    # Find the sequence tiles in hand
    sequence =
      case tile.value - with_tile.value do
        -1 ->
          [tile.value, with_tile.value, with_tile.value + 1]

        -2 ->
          [tile.value, tile.value + 1, with_tile.value]

        1 ->
          [with_tile.value, tile.value, tile.value + 1]

        2 ->
          [with_tile.value, tile.value - 1, tile.value]
      end

    # Remove the two tiles used to form the chow from hand
    hand = []
    # sequence
    # |> List.delete(with_tile.value)
    # |> Enum.reduce(
    #   player.hand,
    #   fn value, acc -> List.delete(acc, %Tile{suit: with_tile.suit, value: value}) end
    # )

    # Add the chow sequence to open hand
    chow_set = []
    # sequence
    # |> Enum.map(fn value ->
    #   %Mahjong.Tile{suit: with_tile.suit, value: value}
    # end)
    # |> List.to_tuple()

    open_hand = [chow_set | player.open_hand]

    %{player | hand: hand, open_hand: open_hand}
  end

  def kong(player, _tile \\ nil), do: player
  def eyes(), do: nil
  def win?(_player), do: false
end
