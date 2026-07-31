defmodule LineWebWeb.Router do
  use LineWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LineWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LineWebWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api/playtest", LineWebWeb do
    pipe_through :api

    post "/sessions", PlaytestController, :create
    get "/sessions/:token", PlaytestController, :show
    post "/sessions/:token/cmd", PlaytestController, :command
    get "/sessions/:token/feed", PlaytestController, :feed
    delete "/sessions/:token", PlaytestController, :delete
  end

  scope "/api", LineWebWeb do
    pipe_through :api

    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end
end
