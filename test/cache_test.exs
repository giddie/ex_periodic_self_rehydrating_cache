defmodule CacheTest do
  @moduledoc false

  use ExUnit.Case, async: true

  setup do
    Cache.clear()
    %{}
  end

  test "unregistered key" do
    assert {:error, :not_registered} = Cache.get(:key)
  end

  test "register a function and get a value" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               200,
               100
             )

    assert Cache.get(:key) == :value
  end

  test "second registration with the same key" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               200,
               100
             )

    assert {:error, :already_registered} =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               200,
               100
             )
  end

  test "value function should be called before the first get" do
    test_pid = self()

    value_function = fn ->
      send(test_pid, :value_function_called)
      {:ok, :value}
    end

    assert :ok = Cache.register(:key, value_function, 200, 100)
    assert_receive :value_function_called, 100

    assert Cache.get(:key) == :value

    # It should _not_ have been called again for that get.
    refute_receive :value_function_called, 100
  end

  test "short get timeout" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               200,
               100
             )

    assert Cache.get(:key, 100) == :value
    # No further messages should be sent, e.g. from the timeout triggering.
    refute_receive _, 500
  end

  test "long-running value function" do
    value_function = fn ->
      Process.sleep(500)
      {:ok, :value}
    end

    # The value function should have been called asynchronously, so registration should return
    # quickly.
    {elapsed_time_us, :ok} =
      :timer.tc(fn ->
        Cache.register(:key, value_function, 200, 100)
      end)

    assert elapsed_time_us / 1_000 < 100

    # Getting the value with default timeout should block until it's available.
    assert Cache.get(:key) == :value
  end

  test "long-running value function: with short get timeout" do
    value_function = fn ->
      Process.sleep(200)
      {:ok, :value}
    end

    Cache.register(:key, value_function, 200, 100)

    assert {:error, :timeout} = Cache.get(:key, 10)
    refute_receive _, 500
  end

  test "value function raises" do
    assert :ok =
             Cache.register(
               :key,
               fn -> raise "value function error" end,
               200,
               100
             )

    assert {:error, :timeout} = Cache.get(:key, 100)
  end

  test "value function returns an error" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:error, "value function error"} end,
               200,
               100
             )

    assert {:error, :timeout} = Cache.get(:key, 100)
  end
end
