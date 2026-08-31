defmodule MahjongWeb.HallLiveTest do
  use MahjongWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "开新局"
  end

  test "there is at least one game in the hall", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#games .room-row")
  end

  test "A player can join the game", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    rendered = render(view)

    assert rendered =~ ~r/<div id="([^"]+)" class="room-row"/
    [_, id] = Regex.run(~r/<div id="([^"]+)" class="room-row"/, rendered)

    join_button =
      element(view, "button[phx-click=\"join\"][phx-value-id=\"#{id}\"]")

    assert join_button |> has_element?()

    join_button |> render_click()
    assert_redirect(view, ~p"/game/#{id}")
  end
end
