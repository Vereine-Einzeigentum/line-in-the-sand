defmodule LineSharedTest do
  use ExUnit.Case
  doctest LineShared

  test "greets the world" do
    assert LineShared.hello() == :world
  end
end
