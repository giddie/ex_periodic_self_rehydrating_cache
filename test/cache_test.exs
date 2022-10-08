defmodule CacheTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup do
    {:ok, _pid} = Cache.Server.start_link()
    %{}
  end

  test "unregistered key" do
    assert {:error, :not_registered} = Cache.get(:key)
  end

  test "register a function and get a value" do
    assert :ok =
             Cache.register(
               :key,
               fn -> :value end,
               200,
               100
             )

    assert Cache.get(:key) == :value
  end

  test "second registration with the same key" do
    assert :ok =
             Cache.register(
               :key,
               fn -> :value end,
               200,
               100
             )

    assert {:error, :already_registered} =
             Cache.register(
               :key,
               fn -> :value end,
               200,
               100
             )
  end
end
