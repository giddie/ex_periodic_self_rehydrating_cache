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

  test "value function should be called before the first get" do
    test_pid = self()

    value_function = fn ->
      send(test_pid, :value_function_called)
      :value
    end

    assert :ok = Cache.register(:key, value_function, 200, 100)
    assert_receive :value_function_called, 100

    assert Cache.get(:key) == :value

    # It should _not_ have been called again for that get.
    refute_receive :value_function_called, 100
  end
end
