defmodule EclawTest do
  use ExUnit.Case
  doctest Eclaw

  test "greets the world" do
    assert Eclaw.hello() == :world
  end
end
