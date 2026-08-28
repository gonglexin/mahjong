defmodule Mahjong.Game do
  @moduledoc """
  麻将对局 GenServer：发牌、轮流摸牌、出牌、吃/碰/杠/胡判定与结算。

  状态字段：
    * `:phase` — `:waiting | :playing | :over`
    * `:dealer` — 庄家座位（东风位开局）
    * `:turn` — 当前该出牌/行动的玩家 id
    * `:last_discard` — `{player_id, tile}` 待吃碰杠胡的弃牌
    * `:pending` — 报牌窗口 `%{eligible: [player_id], responses: %{}, timer: ref}`
    * `:discards_made` — 全局出牌计数（判定天胡/地胡）
    * `:kong_draw?` — 上一次摸牌是否为杠后补牌（杠上开花）
    * `:result` — 对局结果（胡牌番型 / 荒庄）
  """

  use GenServer

  alias Mahjong.{Deck, Player, Rules, Tile}

  @ai_token_prefix "ai-"
  @claim_timeout_ms 10_000
  @turn_order [:east, :south, :west, :north]

  # -- Public API ------------------------------------------------------------

  def new(id) do
    state = {:ok, game} = GenServer.start(__MODULE__, id, name: String.to_atom(id))

    :pg.join(:global, :game_servers, game)

    Mahjong.broadcast("games", {:new_game, String.to_atom(id)})

    state
  end

  def get(id) do
    case Process.whereis(String.to_atom(id)) do
      nil -> {:error, nil}
      game -> {:ok, game}
    end
  end

  def get_id(game), do: GenServer.call(game, :id)
  def join(game, player), do: GenServer.call(game, {:join, player})
  def all_games, do: :pg.get_members(:global, :game_servers)
  def start(game), do: GenServer.call(game, :start)
  def start_by_ai(game), do: GenServer.call(game, :start_by_ai)
  def reset(game), do: GenServer.call(game, :reset)
  def players(game), do: GenServer.call(game, :players)
  def tiles(game), do: GenServer.call(game, :tiles)
  def state(game), do: GenServer.call(game, :state)
  def action(game, player_id, action), do: GenServer.call(game, {player_id, action})

  # -- GenServer -------------------------------------------------------------

  @impl true
  def init(id) do
    {:ok,
     %{
       id: id,
       tiles: [],
       players: [],
       phase: :waiting,
       dealer: nil,
       turn: nil,
       last_discard: nil,
       pending: nil,
       discards_made: 0,
       kong_draw?: false,
       result: nil
     }}
  end

  @impl true
  def handle_call(:state, _, state), do: {:reply, state, state}

  def handle_call(:start, _, %{players: players} = state) when length(players) == 4 do
    dealt = deal_and_start(state)
    {:reply, dealt, dealt}
  end

  def handle_call(:start, _, state), do: {:reply, state, state}

  def handle_call(:start_by_ai, _, %{id: id, players: players} = state) do
    ai_players =
      players
      |> available_positions()
      |> Enum.map(fn position ->
        Player.new(token: "#{@ai_token_prefix}#{position}", position: position, game_id: id)
      end)

    dealt = deal_and_start(%{state | id: id, players: players ++ ai_players})
    {:reply, dealt, dealt}
  end

  def handle_call(:reset, _, %{id: id, players: players} = state) do
    players =
      Enum.map(
        players,
        &%{&1 | hand: [], open_hand: [], discards: [], in_turn?: false, won?: false}
      )

    state = %{
      state
      | id: id,
        players: players,
        tiles: [],
        phase: :waiting,
        dealer: nil,
        turn: nil,
        last_discard: nil,
        pending: nil,
        discards_made: 0,
        kong_draw?: false,
        result: nil
    }

    broadcast(state)
    {:reply, state, state}
  end

  @impl true
  def handle_call(:id, _, %{id: id} = state), do: {:reply, id, state}

  def handle_call(:tiles, _, %{tiles: tiles} = state), do: {:reply, tiles, state}

  def handle_call(:players, _, %{players: players} = state), do: {:reply, players, state}

  def handle_call({:join, player}, _, %{players: players} = state) when length(players) == 4,
    do: {:reply, player, state}

  def handle_call({:join, player = %Player{}}, _, %{id: id, players: players} = state) do
    if is_nil(player.game_id) && player not in players do
      position = players |> available_positions() |> List.first()
      player = %{player | position: position, game_id: id}
      state = %{state | players: [player | players]}

      {:registered_name, game_name} = Process.info(self(), :registered_name)

      # Broadcast to hall live
      Mahjong.broadcast("games", {:player_join, game_name})
      # Broadcast to specific game
      broadcast(state)

      {:reply, player, state}
    else
      {:reply, player, state}
    end
  end

  # -- 出牌 -------------------------------------------------------------------

  def handle_call({player_id, {:discard, tile}}, _, %{phase: :playing, pending: nil} = state) do
    player = find_player(state, player_id)

    if player && state.turn == player_id && Tile.count(player.hand, tile) >= 1 do
      player = Player.discard(player, tile)

      state = %{
        state
        | players: replace_player(state.players, player),
          last_discard: {player_id, tile},
          discards_made: state.discards_made + 1,
          kong_draw?: false,
          turn: nil
      }

      options = claim_options(state, tile, player_id)

      state =
        cond do
          # 胡 > 碰/杠 > 吃：按优先级依次开窗，前一阶段全部放弃才进入下一阶段
          options.win != %{} ->
            state = start_claim_window(state, :win, options.win, options.take, options.chow)
            if all_passed?(state), do: resolve_window(state), else: state

          options.take != %{} ->
            state = start_claim_window(state, :take, options.take, nil, options.chow)
            if all_passed?(state), do: resolve_window(state), else: state

          options.chow != %{} ->
            state = start_claim_window(state, :chow, options.chow, nil, nil)
            if all_passed?(state), do: resolve_window(state), else: state

          true ->
            draw_next(state)
        end

      broadcast(state)
      {:reply, state, state}
    else
      {:reply, {:error, :not_your_turn}, state}
    end
  end

  def handle_call({player_id, :pass}, _, %{pending: pending} = state) when not is_nil(pending) do
    if player_id in pending.eligible do
      pending = %{pending | responses: Map.put(pending.responses, player_id, :pass)}
      state = %{state | pending: pending}

      state =
        if all_passed?(state) do
          resolve_window(state)
        else
          state
        end

      broadcast(state)
      {:reply, state, state}
    else
      {:reply, {:error, :not_eligible}, state}
    end
  end

  def handle_call({player_id, {:chow, base}}, _, %{phase: :playing} = state) do
    with %{pending: %{phase: :chow} = pending} when not is_nil(pending) <- state,
         {discarder_id, tile} <- state.last_discard,
         # 吃只能在吃阶段，且仅限下家
         true <- player_id == next_player_id(state.players, discarder_id),
         true <- player_id in pending.eligible,
         %Player{} = player <- find_player(state, player_id),
         true <- valid_chow?(player.hand, tile, base) do
      player = Player.chow(player, tile, base, discarder_id)
      state = apply_claim(state, player, discarder_id, tile)

      broadcast(state)
      {:reply, state, state}
    else
      _ -> {:reply, {:error, :invalid_claim}, state}
    end
  end

  def handle_call({player_id, {:pong, _} = action}, _, %{phase: :playing} = state) do
    handle_claim_kong_pong(state, player_id, action)
  end

  def handle_call({player_id, {:kong_open}}, _, %{phase: :playing} = state) do
    handle_claim_kong_pong(state, player_id, {:kong_open})
  end

  # -- 胡（点炮 / 自摸）--------------------------------------------------------

  def handle_call({player_id, :win}, _, %{phase: :playing} = state) do
    cond do
      # 点炮：报牌窗口内胡别人打出的牌（先到先得即截胡）
      match?(%{phase: :win, eligible: _}, state.pending) and win_on_discard?(state, player_id) ->
        {_discarder_id, tile} = state.last_discard
        player = find_player(state, player_id)

        case Rules.check(player.hand ++ [tile], player.open_hand) do
          {:win, fans, score} ->
            player = Player.win(%{player | hand: player.hand ++ [tile]})
            discarder_id = elem(state.last_discard, 0)

            state = %{
              state
              | players: replace_player(state.players, player),
                phase: :over,
                pending: nil,
                last_discard: nil,
                result: %{
                  type: :discard_win,
                  winner_id: player_id,
                  loser_id: discarder_id,
                  fans: fans,
                  score: score
                }
            }

            broadcast(state)
            {:reply, state, state}

          :no_win ->
            {:reply, {:error, :not_winning}, state}
        end

      # 自摸
      state.turn == player_id and is_nil(state.pending) ->
        player = find_player(state, player_id)

        flags = self_win_flags(state, player)

        case Rules.check(player.hand, player.open_hand, flags) do
          {:win, fans, score} ->
            player = Player.win(player)

            state = %{
              state
              | players: replace_player(state.players, player),
                phase: :over,
                result: %{type: :self_win, winner_id: player_id, fans: fans, score: score}
            }

            broadcast(state)
            {:reply, state, state}

          :no_win ->
            {:reply, {:error, :not_winning}, state}
        end

      true ->
        {:reply, {:error, :not_your_turn}, state}
    end
  end

  # -- 杠（暗杠 / 加杠），自己回合内 -------------------------------------------

  def handle_call({player_id, {:kong_concealed, tile}}, _, %{phase: :playing} = state) do
    player = find_player(state, player_id)

    with true <- state.turn == player_id and is_nil(state.pending),
         %Player{} = player,
         true <- Tile.count(player.hand, tile) == 4 do
      player = Player.kong_concealed(player, tile)
      state = draw_for_kong(%{state | players: replace_player(state.players, player)})

      broadcast(state)
      {:reply, state, state}
    else
      _ -> {:reply, {:error, :invalid_kong}, state}
    end
  end

  def handle_call({player_id, {:kong_added, tile}}, _, %{phase: :playing} = state) do
    player = find_player(state, player_id)

    with true <- state.turn == player_id and is_nil(state.pending),
         %Player{} = player,
         meld when not is_nil(meld) <- Enum.find(player.open_hand, &(&1.type == :pong)),
         true <- Tile.same?(hd(meld.tiles), tile),
         true <- Tile.count(player.hand, tile) >= 1 do
      player = Player.kong_added(player, tile)
      state = draw_for_kong(%{state | players: replace_player(state.players, player)})

      broadcast(state)
      {:reply, state, state}
    else
      _ -> {:reply, {:error, :invalid_kong}, state}
    end
  end

  def handle_call({_player_id, action}, _, state) do
    {:reply, {:error, {:unknown_action, action}}, state}
  end

  # -- 报牌超时 ----------------------------------------------------------------

  @impl true
  # 超时视为窗口内所有人放弃，同样要激活延迟的下家吃牌
  def handle_info(:claim_timeout, %{pending: pending} = state) when not is_nil(pending) do
    pending = %{pending | responses: Map.new(pending.eligible, fn id -> {id, :pass} end)}

    state = resolve_window(%{state | pending: pending})
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(:claim_timeout, state), do: {:noreply, state}

  # -- 内部：开局与发牌 ---------------------------------------------------------

  defp deal_and_start(%{players: players} = state) do
    tiles = Deck.shuffle()
    {hands, tiles} = deal_hands(players, tiles)

    players =
      players
      |> Enum.zip(hands)
      |> Enum.map(fn {%Player{} = player, hand} ->
        %Player{player | hand: hand, open_hand: [], discards: [], in_turn?: false, won?: false}
      end)

    dealer = Enum.find(players, &(&1.position == :east))
    [tile | tiles] = tiles
    dealer = Player.draw(dealer, tile)

    players = replace_player(players, dealer)

    state = %{
      state
      | players: players,
        tiles: tiles,
        phase: :playing,
        dealer: :east,
        turn: dealer.id,
        last_discard: nil,
        pending: nil,
        discards_made: 0,
        kong_draw?: false,
        result: nil
    }

    broadcast(state)
    state
  end

  defp deal_hands(players, tiles) do
    Enum.map_reduce(players, tiles, fn _player, acc ->
      {hand, rest} = Enum.split(acc, 13)
      {Player.sort_hand(hand), rest}
    end)
  end

  # -- 内部：报牌窗口 -----------------------------------------------------------

  # 开指定阶段的报牌窗口。take/chow 为后续阶段的动作表，随窗口携带
  defp start_claim_window(state, phase, claims, take, chow) do
    eligible = Map.keys(claims)

    # AI 玩家自动过
    {ai_ids, human_ids} =
      Enum.split_with(eligible, fn player_id ->
        state |> find_player(player_id) |> ai?()
      end)

    responses = Map.new(ai_ids, fn player_id -> {player_id, :pass} end)

    timer =
      if human_ids == [] do
        nil
      else
        Process.send_after(self(), :claim_timeout, @claim_timeout_ms)
      end

    %{
      state
      | pending: %{
          phase: phase,
          eligible: eligible,
          responses: responses,
          timer: timer,
          actions: claims,
          take: take || %{},
          chow: chow || %{}
        }
    }
  end

  # 当前阶段全部表态完毕后推进：胡 →(放弃)→ 碰/杠 →(放弃)→ 吃 → 摸牌
  defp resolve_window(state) do
    if all_passed?(state) do
      pending = state.pending
      state = cancel_timer(state)

      cond do
        pending.phase == :win and pending.take != %{} ->
          state = start_claim_window(state, :take, pending.take, nil, pending.chow)
          if all_passed?(state), do: resolve_window(state), else: state

        pending.chow != %{} ->
          state = start_claim_window(state, :chow, pending.chow, nil, nil)
          if all_passed?(state), do: resolve_window(state), else: state

        true ->
          draw_next(state)
      end
    else
      state
    end
  end

  # 计算各家对弃牌可执行的动作，按优先级分三个阶段：
  #   * 胡（:win）：任何位置
  #   * 碰/杠（:take）：任何位置
  #   * 吃（:chow）：仅限下家
  # 同一玩家可同时出现在多个阶段（如既能胡又能碰：先问胡，放弃后再问碰）
  defp claim_options(state, tile, discarder_id) do
    next_id = next_player_id(state.players, discarder_id)

    Enum.reduce(state.players, {%{}, %{}, %{}}, fn player, {win, take, chow} ->
      if player.id == discarder_id do
        {win, take, chow}
      else
        actions = Rules.claim_actions(player.hand, player.open_hand, tile)

        win =
          if :win in actions, do: Map.put(win, player.id, [:win]), else: win

        take_actions = Enum.filter(actions, &(&1 in [:pong] or match?({:kong_open}, &1)))

        take =
          if take_actions == [], do: take, else: Map.put(take, player.id, take_actions)

        chow_actions =
          if player.id == next_id do
            Enum.filter(actions, &match?({:chow, _}, &1))
          else
            []
          end

        chow =
          if chow_actions == [], do: chow, else: Map.put(chow, player.id, chow_actions)

        {win, take, chow}
      end
    end)
    |> then(fn {win, take, chow} -> %{win: win, take: take, chow: chow} end)
  end

  defp all_passed?(%{pending: %{eligible: eligible, responses: responses}}) do
    Enum.all?(eligible, &Map.has_key?(responses, &1))
  end

  defp cancel_timer(%{pending: %{timer: timer}} = state) when not is_nil(timer) do
    Process.cancel_timer(timer)
    %{state | pending: nil}
  end

  defp cancel_timer(state), do: %{state | pending: nil}

  defp win_on_discard?(state, player_id) do
    case state.last_discard do
      {discarder_id, tile} when discarder_id != player_id ->
        player = find_player(state, player_id)
        :win in Rules.claim_actions(player.hand, player.open_hand, tile)

      _ ->
        false
    end
  end

  defp apply_claim(state, player, discarder_id, tile) do
    discarder = find_player(state, discarder_id)
    discarder = %{discarder | discards: List.delete(discarder.discards, tile)}

    %{
      state
      | players: state.players |> replace_player(player) |> replace_player(discarder),
        last_discard: nil,
        pending: nil,
        turn: player.id
    }
    |> cancel_timer()
    |> set_turn(player.id)
  end

  defp handle_claim_kong_pong(state, player_id, action) do
    with %{pending: %{phase: :take} = pending} when not is_nil(pending) <- state,
         {discarder_id, tile} <- state.last_discard,
         true <- player_id in pending.eligible,
         %Player{} = player <- find_player(state, player_id),
         true <- valid_claim?(player, tile, action) do
      player =
        case action do
          {:pong, _} -> Player.pong(player, tile, discarder_id)
          {:kong_open} -> Player.kong_open(player, tile, discarder_id)
        end

      state = apply_claim(state, player, discarder_id, tile)

      # 明杠需补牌；碰/吃后直接出牌
      state =
        if action == {:kong_open} do
          draw_for_kong(state)
        else
          state
        end

      broadcast(state)
      {:reply, state, state}
    else
      _ -> {:reply, {:error, :invalid_claim}, state}
    end
  end

  defp valid_claim?(player, tile, {:pong, _}), do: Tile.count(player.hand, tile) >= 2
  defp valid_claim?(player, tile, {:kong_open}), do: Tile.count(player.hand, tile) >= 3

  defp valid_chow?(hand, tile, base) do
    base >= 1 and base + 2 <= 9 and tile.value in [base, base + 1, base + 2] and
      Enum.all?(for(v <- base..(base + 2), v != tile.value, do: v), fn v ->
        Tile.count(hand, %{tile | value: v}) >= 1
      end)
  end

  # -- 内部：摸牌与轮转 ---------------------------------------------------------

  defp draw_next(state) do
    case state.tiles do
      [] ->
        %{state | phase: :over, last_discard: nil, result: %{type: :wall_empty}}

      [tile | rest] ->
        next_id = next_player_id(state.players, state.turn || elem(state.last_discard, 0))
        player = find_player(state, next_id)
        player = Player.draw(player, tile)

        %{
          state
          | tiles: rest,
            players: replace_player(state.players, player),
            turn: player.id,
            last_discard: nil,
            kong_draw?: false
        }
        |> set_turn(player.id)
    end
  end

  defp draw_for_kong(state) do
    case state.tiles do
      [] ->
        %{state | phase: :over, last_discard: nil, result: %{type: :wall_empty}}

      [tile | rest] ->
        player = find_player(state, state.turn)
        player = Player.draw(player, tile)

        %{
          state
          | tiles: rest,
            players: replace_player(state.players, player),
            kong_draw?: true,
            last_discard: nil
        }
    end
  end

  # 东→南→西→北 逆时针轮转
  defp next_player_id(players, current_id) do
    current = find_player(players, current_id)
    index = Enum.find_index(@turn_order, &(&1 == current.position))

    next_position = Enum.at(@turn_order, rem(index + 1, 4))

    Enum.find(players, &(&1.position == next_position)).id
  end

  defp set_turn(state, turn_id) do
    players =
      Enum.map(state.players, fn player ->
        %{player | in_turn?: player.id == turn_id}
      end)

    %{state | players: players, turn: turn_id}
  end

  defp self_win_flags(state, player) do
    flags = [:self_draw]

    flags =
      if state.kong_draw? do
        [:kong_blossom | flags]
      else
        flags
      end

    cond do
      state.discards_made == 0 and player.position == state.dealer ->
        [:heavenly | flags]

      state.discards_made == 0 ->
        [:earthly | flags]

      true ->
        flags
    end
  end

  # -- 内部：工具 ---------------------------------------------------------------

  defp available_positions(players) do
    taken = Enum.map(players, & &1.position)
    Enum.reject(Deck.positions(), &(&1 in taken))
  end

  defp ai?(player),
    do: is_binary(player.token) and String.starts_with?(player.token, @ai_token_prefix)

  defp find_player(%{players: players}, player_id), do: find_player(players, player_id)

  defp find_player(players, player_id) when is_list(players) do
    Enum.find(players, &(&1.id == player_id))
  end

  defp replace_player(players, player) do
    Enum.map(players, fn p -> if p.id == player.id, do: player, else: p end)
  end

  defp broadcast(state), do: Mahjong.broadcast("games:#{state.id}", {:game_update, state})
end
