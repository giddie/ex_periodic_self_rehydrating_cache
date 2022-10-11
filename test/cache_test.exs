defmodule CacheTest do
  @moduledoc false

  use ExUnit.Case, async: false

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
               1_000,
               500
             )

    assert {:ok, :value} == Cache.get(:key)
  end

  test "second registration with the same key" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               1_000,
               500
             )

    assert {:error, :already_registered} =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               1_000,
               500
             )
  end

  test "value function should be called before the first get" do
    test_pid = self()

    value_function = fn ->
      send(test_pid, :value_function_called)
      {:ok, :value}
    end

    assert :ok = Cache.register(:key, value_function, 1_000, 500)
    assert_receive :value_function_called, 100

    assert {:ok, :value} == Cache.get(:key)

    # It should _not_ have been called again for that get.
    refute_receive :value_function_called, 100
  end

  test "short get timeout" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:ok, :value} end,
               1_000,
               500
             )

    assert {:ok, :value} == Cache.get(:key, 100)
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
        Cache.register(:key, value_function, 1_000, 500)
      end)

    assert elapsed_time_us / 1_000 < 100

    # Getting the value with default timeout should block until it's available.
    assert {:ok, :value} == Cache.get(:key)
  end

  test "long-running value function: with short get timeout" do
    value_function = fn ->
      Process.sleep(200)
      {:ok, :value}
    end

    Cache.register(:key, value_function, 1_000, 500)

    assert {:error, :timeout} = Cache.get(:key, 10)
    refute_receive _, 500
  end

  test "value function raises" do
    assert :ok =
             Cache.register(
               :key,
               fn -> raise "value function error" end,
               1_000,
               500
             )

    assert {:error, :timeout} = Cache.get(:key, 100)
  end

  test "value function returns an error" do
    assert :ok =
             Cache.register(
               :key,
               fn -> {:error, "value function error"} end,
               1_000,
               500
             )

    assert {:error, :timeout} = Cache.get(:key, 100)
  end

  test "value function returns different value on subsequent call" do
    Cache.register(:key, get_mock_value_function(), 500, 200)

    send_next_mock_value({:ok, "First"})
    assert {:ok, "First"} = Cache.get(:key)

    # The next value won't be requested until the refresh interval is reached.
    {elapsed_time_us, _value} =
      :timer.tc(fn ->
        send_next_mock_value({:ok, "Second"})
      end)

    assert elapsed_time_us > 150_000
    assert elapsed_time_us < 250_000

    assert {:ok, "Second"} = Cache.get(:key)
  end

  test "value function successful at first, then errors" do
    Cache.register(:key, get_mock_value_function(), 300, 100)

    # 100ms
    send_next_mock_value({:ok, "First"})

    assert {:ok, "First"} = Cache.get(:key)

    # 100ms
    send_next_mock_value({:error, "Failed"})

    assert {:ok, "First"} = Cache.get(:key)

    # 200ms
    Process.sleep(200)

    # Now we've hit the TTL
    assert {:error, :timeout} = Cache.get(:key, 10)

    # A good value will make it all right again.
    # TTL is reset
    send_next_mock_value({:ok, "Third"})
    assert {:ok, "Third"} = Cache.get(:key)

    # 200ms
    Process.sleep(200)
    assert {:ok, "Third"} = Cache.get(:key)

    # 200ms
    Process.sleep(200)

    # TTL has expired again
    assert {:error, :timeout} = Cache.get(:key, 10)
  end

  @spec get_mock_value_function() :: any()
  defp get_mock_value_function() do
    test_pid = self()

    fn ->
      send(test_pid, {:send_next_to, self()})

      receive do
        {:next, value} ->
          send(test_pid, :ok)
          value
      end
    end
  end

  @spec send_next_mock_value(value) :: value when value: any()
  defp send_next_mock_value(value) do
    receive do
      {:send_next_to, pid} ->
        send(pid, {:next, value})

        receive do
          :ok -> :ok
        end
    end
  end
end
