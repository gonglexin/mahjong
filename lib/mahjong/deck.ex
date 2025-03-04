defmodule Mahjong.Deck do
  alias Mahjong.Tile

  @positions [:east, :south, :west, :north]

  def shuffle() do
    tiles =
      for suit <- Tile.suits(),
          value <- 1..9,
          _ <- 1..4,
          do: %Tile{suit: suit, value: value}

    Enum.shuffle(tiles)
  end

  def new_hand(tiles) do
    {hand, left_tiles} = Enum.split(tiles, 13)

    sorted_hand =
      hand
      |> Enum.sort_by(fn tile ->
        {tile.suit, tile.value}
      end)

    {sorted_hand, left_tiles}
  end

  def four_hands(tiles) do
    {first_hand, tiles} = new_hand(tiles)
    {sencond_hand, tiles} = new_hand(tiles)
    {third_hand, tiles} = new_hand(tiles)
    {fourth_hand, tiles} = new_hand(tiles)
    {[first_hand, sencond_hand, third_hand, fourth_hand], tiles}
  end

  # TODO: Fix this
  def next([]) do
    raise "Empty deck"
  end

  def next(tiles) do
    [tile | left_tiles] = tiles
    {tile, left_tiles}
  end

  def positions, do: @positions
end
