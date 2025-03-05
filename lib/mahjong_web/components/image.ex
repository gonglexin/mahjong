defmodule MahjongWeb.Components.Image do
  @moduledoc """
  Provides the UI for rendering avatars/images.

  Use ES modules from [Minidenticons](https://github.com/laurentpayot/minidenticons).

  Must add this script in head:


  ```javascript
    <script type="module">
      import { minidenticonSvg } from 'https://cdn.jsdelivr.net/npm/minidenticons@4.2.1/minidenticons.min.js'
    </script>
  ```
  """
  use Phoenix.Component

  @doc """
  Renders a avatar
  ## Examples

      <.avatar name="uuid" />
      <.avatar name={player.token} class="ml-1 w-3 h-3" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def avatar(assigns) do
    ~H"""
    <div id={@name} phx-update="ignore" class={["w-10 rounded-[50%] bg-gray-200", @class]}>
      <minidenticon-svg username={@name}></minidenticon-svg>
    </div>
    """
  end

  @doc """
  Renders a game room (a game server)
  ## Examples

      <.room name="game_id" />
      <.room name={game.id} class="ml-1 w-3 h-3" />
  """
  attr :id, :string, required: true
  attr :class, :string, default: nil

  def room(assigns) do
    ~H"""
    <div id={@id} phx-update="ignore" class={["w-10 h-10 bg-purple-100/50", @class]}>
      <minidenticon-svg username={@id}></minidenticon-svg>
    </div>
    """
  end
end
