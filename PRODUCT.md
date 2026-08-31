# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

开发者与朋友：桌面浏览器为主，开一个房间四人同桌（可补 AI），随时来一局中式麻将。观战者可旁观牌局。

## Product Purpose

实时多人在线中国麻将：Phoenix LiveView 房间制，四人同桌，缺位可由 AI（persona）补齐。完整对局流程（开局 → 行牌 → 胡牌/荒庄结算，番种计分），局内可碰/杠/吃/胡/过。成功 = 一局牌从进房到结算顺畅、可读、无歧义。

## Positioning

无需注册、链接即入局的轻量麻将房：房间即进程，进链接坐下就能打；AI persona 让凑不齐四人时也能开局。

## Operating Context

- 牌桌术语全部中文：东/南/西/北风位、碰/杠/吃/胡/过、番种名、自摸/放炮/荒庄。
- 房间通过 URL 分享进入；大厅列出所有活跃房间。
- 玩家无账号，以 session token 标识，头像为 minidenticon。

## Capabilities and Constraints

- 座位视角以当前玩家为 bottom，其余按风位旋转映射；罗盘显示当前风位与余牌数。
- 刚摸的牌不参与排序，置于手牌末端并留间距；报牌窗口中等待者显示"等待其他玩家行动"。
- 阶段：waiting（加 AI/开始）→ playing → over（结算横幅 + 再来一局）。
- 技术约束：Phoenix 1.8 / LiveView streams / Tailwind v4 / daisyUI 已接入；牌桌有大量绝对定位座位布局。

## Brand Commitments

- **现有牌面 GIF 必须保留**（用户确认）：priv/static/images/ 下 characters_N / dots_N / bamboos_N .gif 与 hidden_tile.gif 是唯一牌面素材来源。
- priv/static/images/I.MahjongCAN.otf 字体文件已在库中，可选用。

## Evidence on Hand

- 牌面素材：priv/static/images/{characters,dots,bamboos}_{1..9}.gif、hidden_tile.gif。
- 房间/玩家标识：minidenticon（CDN ES module）。

## Product Principles

1. 牌局状态永远一眼可读：轮到谁、余牌多少、能不能动作，不许靠猜。
2. 术语零学习成本：碰/杠/吃/胡 按麻将母语呈现，不做翻译游戏。
3. 进局零门槛：链接即入座，观战不干扰。
4. 桌面优先，紧凑高效：信息密度服务于行牌决策，而非装饰。

## Accessibility & Inclusion

未确立产品级专项要求；沿用浏览器默认可达性基线。
