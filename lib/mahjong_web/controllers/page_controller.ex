defmodule MahjongWeb.PageController do
  use MahjongWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
