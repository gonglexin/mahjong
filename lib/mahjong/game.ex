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
  @turn_order [:east, :south, :west, :north]
  @ai_claim_delay_ms 700

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
  def add_ai(game, persona), do: GenServer.call(game, {:add_ai, persona})
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
       result: nil,
       ai_timer: nil
     }}
  end

  @impl true
  def handle_call(:state, _, state), do: {:reply, state, state}

  def handle_call(:start, _, %{players: players} = state) when length(players) == 4 do
    dealt = deal_and_start(state)
    {:reply, dealt, dealt}
  end

  def handle_call(:start, _, state), do: {:reply, state, state}

  # 添加一名指定性格的 AI 玩家到空位（不自动开局）
  def handle_call({:add_ai, persona}, _, %{id: id, players: players} = state) do
    case available_positions(players) do
      [] ->
        {:reply, {:error, :table_full}, state}

      [position | _] ->
        ai =
          Player.new(
            token: "#{@ai_token_prefix}#{position}-#{:erlang.unique_integer([:positive])}",
            position: position,
            game_id: id,
            persona: persona
          )

        state = %{state | players: [ai | players]}

        {:registered_name, game_name} = Process.info(self(), :registered_name)
        Mahjong.broadcast("games", {:player_join, game_name})
        broadcast(state)

        {:reply, {:ok, ai}, state}
    end
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
        result: nil,
        ai_timer: nil
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

    # 按唯一 id 校验：手牌有两张相同牌时，防止同一张牌的事件被重复处理
    if player && state.turn == player_id && Enum.any?(player.hand, &(&1.id == tile.id)) do
      player = Player.discard(player, tile)

      state = %{
        state
        | players: replace_player(state.players, player),
          last_discard: {player_id, tile},
          discards_made: state.discards_made + 1,
          kong_draw?: false,
          turn: nil
      }

      claims = merge_claim_actions(claim_options(state, tile, player_id))

      state =
        if claims == %{} do
          draw_next(state)
        else
          # 合并报牌：胡/碰/杠/吃按钮同窗出现，全员表态后按 胡 > 杠/碰 > 吃 结算
          state = start_claim_window(state, claims)
          if all_passed?(state), do: resolve_window(state), else: state
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
    with %{pending: pending} when not is_nil(pending) <- state,
         true <- player_id in pending.eligible,
         {:chow, _} = action <-
           Enum.find(Map.get(pending.actions, player_id, []), &match?({:chow, _}, &1)),
         {_discarder_id, tile} <- state.last_discard,
         %Player{} = player <- find_player(state, player_id),
         true <- valid_chow?(player.hand, tile, base) do
      state = record_claim(state, player_id, action)

      broadcast(state)
      {:reply, state, state}
    else
      _ -> {:reply, {:error, :invalid_claim}, state}
    end
  end

  def handle_call({player_id, {:pong, _} = action}, _, %{phase: :playing} = state) do
    record_take_claim(state, player_id, action)
  end

  def handle_call({player_id, {:kong_open} = action}, _, %{phase: :playing} = state) do
    record_take_claim(state, player_id, action)
  end

  # -- 胡（点炮 / 自摸）--------------------------------------------------------

  def handle_call({player_id, :win}, _, %{phase: :playing} = state) do
    cond do
      # 点炮：报牌窗口内声明胡（结算在全员表态后按 胡 > 碰/杠 > 吃 定夺）
      match?(%{eligible: _}, state.pending) and win_claim?(state, player_id) ->
        state = record_claim(state, player_id, :win)

        broadcast(state)
        {:reply, state, state}

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
         meld when not is_nil(meld) <-
           Enum.find(player.open_hand, &(&1.type == :pong and Tile.same?(hd(&1.tiles), tile))),
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

  # AI 回合：思考延迟后决策（胡/暗杠/加杠/出牌），复用既有校验路径
  # 遗留兼容：热重载前旧窗口的定时器消息（新流程不再使用超时），安全忽略
  def handle_info(:claim_timeout, state), do: {:noreply, state}

  @impl true
  def handle_info({:ai_act, player_id}, state) do
    player = find_player(state, player_id)

    if player && ai?(player) && state.phase == :playing && is_nil(state.pending) &&
         state.turn == player_id do
      ctx = %{wall_left: length(state.tiles)}
      action = Mahjong.AI.decide_turn(player, ctx)

      {:reply, _reply, new_state} = handle_call({player_id, action}, nil, state)
      broadcast(new_state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # AI 报牌：每次调度处理一位未表态 AI（按座位顺序），其后仍有未表态 AI 则链式续约；
  # 窗口保持开启直到所有玩家（含人类）表态
  def handle_info({:ai_claims, gen}, %{pending: %{gen: gen} = pending} = state) do
    case next_ai_claim(state, pending) do
      :none ->
        {:noreply, state}

      {id, :pass} ->
        {:reply, _reply, new_state} = handle_call({id, :pass}, nil, state)
        new_state = chain_ai_claims(new_state, gen)
        broadcast(new_state)
        {:noreply, new_state}

      {id, action} ->
        claim = normalize_claim(action)
        {:reply, _reply, new_state} = handle_call({id, claim}, nil, state)
        new_state = chain_ai_claims(new_state, gen)
        broadcast(new_state)
        {:noreply, new_state}
    end
  end

  def handle_info({:ai_claims, _gen}, state), do: {:noreply, state}

  # 引擎决策的 :pong 归一化为 handle_call 的 {:pong, nil}
  defp normalize_claim(:pong), do: {:pong, nil}
  defp normalize_claim(action), do: action

  defp next_ai_claim(state, pending) do
    tile = elem(state.last_discard, 1)
    ctx = %{wall_left: length(state.tiles)}

    Enum.find_value(pending.eligible, fn player_id ->
      decided? = Map.has_key?(pending.responses, player_id)
      player = find_player(state, player_id)

      if (not decided? and player) && ai?(player) do
        actions = Map.get(pending.actions, player_id, [])
        decision = Mahjong.AI.decide_claim(player, tile, actions, ctx)
        {player_id, decision}
      end
    end)
  end

  defp chain_ai_claims(%{pending: %{gen: gen}} = state, gen) do
    if any_undecided_ai?(state), do: schedule_ai_claims(state, gen), else: state
  end

  defp chain_ai_claims(state, _gen), do: state

  defp any_undecided_ai?(%{pending: %{eligible: eligible, responses: responses}} = state) do
    Enum.any?(eligible, fn player_id ->
      not Map.has_key?(responses, player_id) and
        state |> find_player(player_id) |> ai?()
    end)
  end

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

    state = maybe_schedule_ai_act(state)
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

  # 开合并报牌窗口：claims 为 %{player_id => [动作...]}。
  # 人类玩家无超时（窗口等待其表态）；AI 在延迟后按座位顺序依次决策。
  defp start_claim_window(state, claims) do
    eligible = Map.keys(claims)
    gen = make_ref()

    state = %{state | pending: %{gen: gen, eligible: eligible, actions: claims, responses: %{}}}

    if Enum.any?(eligible, fn player_id -> state |> find_player(player_id) |> ai?() end) do
      schedule_ai_claims(state, gen)
    else
      state
    end
  end

  defp schedule_ai_claims(state, gen) do
    Process.send_after(self(), {:ai_claims, gen}, @ai_claim_delay_ms)
    state
  end

  # 全员表态后结算：胡 > 杠/碰 > 吃，同级按逆时针座位序（先到者截和/截碰）
  defp resolve_window(%{pending: pending} = state) do
    state = %{state | pending: nil}
    discarder_id = elem(state.last_discard, 0)
    claims = Map.reject(pending.responses, fn {_id, response} -> response == :pass end)
    order = claim_priority_order(state, discarder_id)

    cond do
      id = Enum.find(order, &(Map.get(claims, &1) == :win)) ->
        apply_discard_win(state, id)

      id = Enum.find(order, &(Map.get(claims, &1) in [:pong, :kong_open])) ->
        apply_take(state, id, Map.get(claims, id))

      id = Enum.find(order, &match?({:chow, _}, Map.get(claims, &1))) ->
        apply_chow(state, id, Map.get(claims, id))

      true ->
        draw_next(state)
    end
  end

  # 计算各家对弃牌可执行的动作：
  #   * 胡（:win）：任何位置
  #   * 碰/杠（:take）：任何位置
  #   * 吃（:chow）：仅限下家
  # 同一玩家的动作合并为一张同窗按钮列表（如 [:win, :pong]）
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

  defp merge_claim_actions(%{win: win, take: take, chow: chow}) do
    ids = Enum.uniq(Map.keys(win) ++ Map.keys(take) ++ Map.keys(chow))

    Map.new(ids, fn id ->
      actions = Enum.uniq(Map.get(win, id, []) ++ Map.get(take, id, []) ++ Map.get(chow, id, []))
      {id, actions}
    end)
  end

  # 记录响应；全员表态后进入结算
  defp record_claim(%{pending: pending} = state, player_id, action) do
    pending = %{pending | responses: Map.put(pending.responses, player_id, action)}
    state = %{state | pending: pending}
    if all_passed?(state), do: resolve_window(state), else: state
  end

  # 碰/杠响应：校验后按基础动作（:pong/:kong_open）记录
  defp record_take_claim(state, player_id, action) do
    base_action =
      case action do
        {:pong, _} -> :pong
        _ -> :kong_open
      end

    with %{pending: pending} when not is_nil(pending) <- state,
         actions = Map.get(pending.actions, player_id, []),
         true <- has_action?(actions, base_action),
         %Player{} = player <- find_player(state, player_id),
         tile = elem(state.last_discard, 1),
         true <- valid_claim?(player, tile, base_action) do
      state = record_claim(state, player_id, base_action)

      broadcast(state)
      {:reply, state, state}
    else
      _ -> {:reply, {:error, :invalid_claim}, state}
    end
  end

  # 动作表里的杠以元组 {:kong_open} 存储，其余为原子（:pong/:win/{:chow, n}）
  defp has_action?(actions, :kong_open) do
    Enum.any?(actions, &(&1 == :kong_open or match?({:kong_open}, &1)))
  end

  defp has_action?(actions, base_action) do
    base_action in actions
  end

  # 结算优先级的座位序：从弃牌者的下家开始逆时针
  defp claim_priority_order(state, discarder_id) do
    discarder = find_player(state, discarder_id)
    start = Enum.find_index(@turn_order, &(&1 == discarder.position))

    1..(length(@turn_order) - 1)
    |> Enum.map(fn step ->
      position = Enum.at(@turn_order, rem(start + step, length(@turn_order)))

      case Enum.find(state.players, &(&1.position == position)) do
        %Player{} = player -> player.id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp all_passed?(%{pending: %{eligible: eligible, responses: responses}}) do
    Enum.all?(eligible, &Map.has_key?(responses, &1))
  end

  defp win_claim?(%{pending: %{eligible: eligible, actions: actions}}, player_id) do
    player_id in eligible and :win in Map.get(actions, player_id, [])
  end

  # 点炮胡结算（窗口全员表态、胡优先胜出后调用）
  defp apply_discard_win(state, winner_id) do
    {_discarder_id, tile} = state.last_discard
    player = find_player(state, winner_id)

    case Rules.check(player.hand ++ [tile], player.open_hand) do
      {:win, fans, score} ->
        player = Player.win(%{player | hand: player.hand ++ [tile]})
        discarder_id = elem(state.last_discard, 0)

        %{
          state
          | players: replace_player(state.players, player),
            phase: :over,
            pending: nil,
            last_discard: nil,
            result: %{
              type: :discard_win,
              winner_id: winner_id,
              loser_id: discarder_id,
              fans: fans,
              score: score
            }
        }

      :no_win ->
        state
    end
  end

  defp apply_take(state, player_id, action) do
    {discarder_id, tile} = state.last_discard
    player = find_player(state, player_id)
    true = valid_claim?(player, tile, action)

    player =
      if action == :kong_open do
        Player.kong_open(player, tile, discarder_id)
      else
        Player.pong(player, tile, discarder_id)
      end

    state = apply_claim(state, player, discarder_id, tile)

    if action == :kong_open, do: draw_for_kong(state), else: state
  end

  # 吃结算（仅下家可响应）
  defp apply_chow(state, player_id, {:chow, base} = _action) do
    {discarder_id, tile} = state.last_discard
    player = find_player(state, player_id)
    player = Player.chow(player, tile, base, discarder_id)
    apply_claim(state, player, discarder_id, tile)
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
    |> set_turn(player.id)
    |> maybe_schedule_ai_act()
  end

  defp valid_claim?(player, tile, action) do
    count_needed = if action == :pong, do: 2, else: 3
    Tile.count(player.hand, tile) >= count_needed
  end

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
        |> maybe_schedule_ai_act()
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
        |> maybe_schedule_ai_act()
    end
  end

  # 若当前行动玩家是 AI，安排其思考后行动
  defp maybe_schedule_ai_act(state) do
    if state.phase == :playing and is_nil(state.pending) do
      player = state.turn && find_player(state, state.turn)

      if player && ai?(player) do
        state = cancel_ai_timer(state)
        %{state | ai_timer: Process.send_after(self(), {:ai_act, player.id}, ai_think_ms())}
      else
        state
      end
    else
      state
    end
  end

  defp cancel_ai_timer(%{ai_timer: timer} = state) when not is_nil(timer) do
    Process.cancel_timer(timer)
    %{state | ai_timer: nil}
  end

  defp cancel_ai_timer(state), do: %{state | ai_timer: nil}

  defp ai_think_ms, do: ai_config() |> Keyword.get(:think_ms, 1_200)

  defp ai_config, do: Application.get_env(:mahjong, :ai, [])

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
