defmodule Mahjong.AI do
  @moduledoc """
  AI 玩家门面：引擎算合法候选 → LLM 按性格选择（可选）→ 引擎兜底。

  所有决策都经过合法性校验，非法选择一律回退引擎推荐，保证对局状态安全。
  """

  alias Mahjong.{AI.Engine, AI.LLM, Player, Rules, Tile}

  @doc """
  自己回合的决策（已摸牌）。返回 `:win` | `{:kong_concealed, t}` |
  `{:kong_added, t}` | `{:discard, tile}`。
  """
  def decide_turn(%Player{} = player, ctx) do
    legal = Rules.self_actions(player.hand, player.open_hand)

    discard_candidates =
      player.hand
      |> Enum.uniq_by(&Tile.key/1)
      |> Enum.map(&{:discard, &1})

    candidates = legal ++ discard_candidates

    case LLM.decide(player.persona, turn_context(player, ctx), candidates) do
      {:ok, action} ->
        if legal_turn_action?(player, action), do: action, else: Engine.decide_self(player, ctx)

      :skip ->
        Engine.decide_self(player, ctx)
    end
  end

  @doc """
  对弃牌的报牌决策。返回 `:win` | `:pong` | `{:kong_open}` | `{:chow, base}` | `:pass`。
  """
  def decide_claim(%Player{} = player, tile, actions, ctx) do
    case LLM.decide(player.persona, claim_context(player, tile, ctx), actions) do
      {:ok, action} ->
        if action in actions,
          do: action,
          else: Engine.decide_claim(player.persona, player, tile, actions, ctx)

      :skip ->
        Engine.decide_claim(player.persona, player, tile, actions, ctx)
    end
  end

  defp legal_turn_action?(player, {:discard, tile}), do: Tile.count(player.hand, tile) >= 1

  defp legal_turn_action?(player, :win),
    do: match?({:win, _, _}, Rules.check(player.hand, player.open_hand))

  defp legal_turn_action?(%{open_hand: melds} = player, {:kong_concealed, tile}) do
    melds == [] and Tile.count(player.hand, tile) == 4
  end

  defp legal_turn_action?(player, {:kong_added, tile}) do
    Tile.count(player.hand, tile) >= 1 and
      Enum.any?(player.open_hand, fn
        %{type: :pong, tiles: [t | _]} -> Tile.same?(t, tile)
        _ -> false
      end)
  end

  defp legal_turn_action?(_, _), do: false

  defp turn_context(player, ctx) do
    base_context(player, ctx)
    |> Map.put(:actions, [
      Rules.self_actions(player.hand, player.open_hand),
      player.hand |> Enum.uniq_by(&Tile.key/1) |> Enum.map(&{:discard, &1})
    ])
    |> flatten_actions()
  end

  defp claim_context(player, tile, ctx) do
    base_context(player, ctx)
    |> Map.put(:claimed_tile, %{suit: tile.suit, value: tile.value})
    |> Map.put(:actions, [])
    |> flatten_actions()
  end

  defp base_context(player, ctx) do
    %{
      hand: player.hand,
      melds: player.open_hand,
      discards: ctx[:discards] || %{},
      wall_left: ctx[:wall_left] || 0
    }
  end

  # LLM prompt 里的 actions 需要扁平列表
  defp flatten_actions(%{actions: actions} = ctx) when is_list(actions), do: ctx
end
