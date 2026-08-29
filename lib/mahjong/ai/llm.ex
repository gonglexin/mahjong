defmodule Mahjong.AI.LLM do
  @moduledoc """
  可选的 LLM 性格化决策层。

  引擎（Mahjong.AI.Engine）先算出合法候选动作，LLM 只负责按性格选一个；
  未配置 API key、超时或返回非法选择时，调用方应回退到引擎选择。

  配置（config/dev.exs 或运行时）：

      config :mahjong, :ai,
        llm_enabled: true,
        llm_model: "deepseek-chat",           # 推荐 DeepSeek-V3：中文强/便宜/JSON 稳定
        llm_base_url: "https://api.deepseek.com",
        llm_api_key: System.get_env("DEEPSEEK_API_KEY")

  备选模型：智谱 GLM-4-Flash（免费）、OpenAI gpt-4o-mini。
  """

  require Logger

  alias Mahjong.Tile

  defp config, do: Application.get_env(:mahjong, :ai, [])
  defp enabled?, do: Keyword.get(config(), :llm_enabled, false)
  defp model, do: Keyword.get(config(), :llm_model, "deepseek-chat")
  defp base_url, do: Keyword.get(config(), :llm_base_url, "https://api.deepseek.com")
  defp api_key, do: Keyword.get(config(), :llm_api_key)

  @timeout_ms 6_000

  @doc """
  让 LLM 从候选动作中选择。返回 `{:ok, action}` 或 `:skip`（调用方回退引擎）。

    * `persona` — 玩家性格（:greedy | :rational | :casual）
    * `context` — %{
        hand: [tile], melds: [meld], discards: %{position => [tile]},
        wall_left: n, actions: [action], phase: :self | :take | :chow
      }
    * `candidates` — 合法动作列表（与 context.actions 相同）
  """
  def decide(persona, context, candidates) do
    if enabled?() and is_binary(api_key()) and candidates != [] do
      do_decide(persona, context, candidates)
    else
      :skip
    end
  end

  defp do_decide(persona, context, candidates) do
    payload = %{
      model: model(),
      messages: [
        %{role: "system", content: system_prompt(persona)},
        %{role: "user", content: user_prompt(context, candidates)}
      ],
      response_format: %{type: "json_object"},
      temperature: temperature(persona),
      max_tokens: 200
    }

    headers = [{"authorization", "Bearer " <> api_key()}]

    case Req.post("#{base_url()}/chat/completions",
           json: payload,
           headers: headers,
           receive_timeout: @timeout_ms,
           retry: :transient
         ) do
      {:ok, %{status: 200, body: body}} ->
        parse_choice(body, candidates)

      {:ok, %{status: status}} ->
        Logger.warning("AI LLM non-200: #{status}")
        :skip

      {:error, exception} ->
        Logger.warning("AI LLM request failed: #{Exception.message(exception)}")
        :skip
    end
  rescue
    e ->
      Logger.warning("AI LLM decide raised: #{Exception.message(e)}")
      :skip
  end

  defp parse_choice(body, candidates) do
    content =
      body
      |> get_in(["choices", Access.at(0), "message", "content"])
      |> to_string()

    case Jason.decode(content) do
      {:ok, %{"choice" => choice}} when is_binary(choice) ->
        candidate = find_candidate(candidates, choice)

        if candidate, do: {:ok, candidate}, else: :skip

      _ ->
        :skip
    end
  rescue
    _ -> :skip
  end

  # 候选动作序列化：动作 → 可读短语，LLM 返回短语原样即视为选择
  defp find_candidate(candidates, choice) do
    Enum.find(candidates, fn action -> describe(action) == choice end)
  end

  defp describe(:win), do: "win"
  defp describe(:pass), do: "pass"
  defp describe(:pong), do: "pong"
  defp describe({:kong_open}), do: "kong_open"
  defp describe({:kong_concealed, tile}), do: "kong_concealed:#{tile.suit}:#{tile.value}"
  defp describe({:kong_added, tile}), do: "kong_added:#{tile.suit}:#{tile.value}"
  defp describe({:chow, base}), do: "chow:#{base}"
  defp describe({:discard, tile}), do: "discard:#{tile.suit}:#{tile.value}"

  defp temperature(:casual), do: 0.9
  defp temperature(:greedy), do: 0.6
  defp temperature(_), do: 0.2

  # -- Prompt -------------------------------------------------------------------

  defp system_prompt(persona) do
    persona_desc =
      case persona do
        :greedy ->
          "你是一名长沙麻将 AI 玩家「豪哥」，性格是大牌型：不喜欢小胡小碰，" <>
            "愿意放弃平胡/自摸去争取清一色、碰碰胡、七对等大牌。牌面有潜力时果断放弃小利。"

        :rational ->
          "你是一名长沙麻将 AI 玩家「教授」，性格是绝对科学型：凡事以牌面与概率计算。" <>
            "永远选择向听数最优、危险性最低的打法，该胡就胡，不感情用事。"

        :casual ->
          "你是一名长沙麻将 AI 玩家「乐乐」，性格感性随性：打得比较随意，" <>
            "喜欢凭感觉出牌，偶尔冒进，但遇到能胡的牌还是很开心的。"

        _ ->
          "你是一名长沙麻将 AI 玩家。"
      end

    persona_desc <>
      " 规则：长沙麻将（万/筒/条 108 张，258 做将）。" <>
      "你必须从给定候选动作中选择一个，以 JSON 返回：{\"choice\": \"<动作短语>\", \"reason\": \"一句话理由\"}。" <>
      "动作短语必须与候选列表完全一致。"
  end

  defp user_prompt(context, candidates) do
    %{
      我的手牌: describe_tiles(context.hand),
      我的副露: describe_melds(context.melds),
      各家弃牌: Map.new(context.discards || %{}, fn {pos, tiles} -> {pos, describe_tiles(tiles)} end),
      余牌: context.wall_left,
      可选动作: Enum.map(candidates, &describe_action_for_prompt/1)
    }
    |> Jason.encode!(pretty: true)
  end

  defp describe_action_for_prompt(action), do: describe(action)

  defp describe_tiles(tiles) do
    tiles
    |> Enum.group_by(& &1.suit, & &1.value)
    |> Enum.sort_by(fn {suit, _} -> Tile.suit_rank(suit) end)
    |> Enum.map_join(" ", fn {suit, values} ->
      prefix = %{characters: "万", dots: "筒", bamboos: "条"}[suit]
      digits = values |> Enum.sort() |> Enum.map_join("", &to_string/1)
      digits <> prefix
    end)
  end

  defp describe_melds(melds) do
    Enum.map_join(melds, "；", fn meld ->
      name =
        %{pong: "碰", chow: "吃", kong_open: "明杠", kong_concealed: "暗杠", kong_added: "加杠"}[
          meld.type
        ]

      "#{name}(" <> describe_tiles(meld.tiles) <> ")"
    end)
  end
end
