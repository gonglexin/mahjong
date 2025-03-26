defmodule MahjongWeb.HallLiveTest do
  use MahjongWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "New Game"
  end

  test "there is at least one game in the hall", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "tbody#games > tr")
  end

  test "A player can join the game", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    rendered = render(view)

    assert rendered =~ ~r/<tr id="([^"]+)"/
    [_, id] = Regex.run(~r/<tr id="([^"]+)"/, rendered)

    join_button = element(view, "button", "Join")
    assert join_button |> has_element?()

    join_button |> render_click()
    assert_redirect(view, ~p"/game/#{id}")
  end
end
