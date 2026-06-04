defmodule LineWorldTest do
  use ExUnit.Case
  doctest LineWorld

  test "greets the world" do
    assert LineWorld.hello() == :world
  end
end
