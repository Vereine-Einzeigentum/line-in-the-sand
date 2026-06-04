defmodule LineCoreTest do
  use ExUnit.Case
  doctest LineCore

  test "greets the world" do
    assert LineCore.hello() == :world
  end
end
