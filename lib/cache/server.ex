defmodule Cache.Server do
  @moduledoc """
  GenServer implementation for a Periodic Self-Rehydrating Cache

  ## Usage

      iex> Cache.Server.start_link(MyCache)
      iex> Cache.Server.register(
      ...>   MyCache,
      ...>   :my_key,
      ...>   fn -> {:ok, "My Value"} end,
      ...>   10_000,
      ...>   1_000
      ...> )
      :ok
      iex> Cache.Server.get(MyCache, :my_key)
      {:ok, "My Value"}
  """

  alias __MODULE__, as: Self
  alias Cache.Private.CallAwaitingResponse
  alias Cache.Private.Registration
  alias Cache.Private.State

  use GenServer

  # Client

  @doc """
  ## Arguments

    - `name`: atom to be used as unique name for this cache.
  """
  @spec start_link([] | atom()) :: {:ok, pid()}
  def start_link(name \\ Self)

  def start_link([]), do: start_link()

  def start_link(name) when is_atom(name) do
    GenServer.start_link(Self, State.new(name), name: name)
  end

  @doc """
  Registers a function that will be computed periodically to update the cache.

  ## Arguments

    - `key`: associated with the function and is used to retrieve the stored value.
    - `function`: a 0-arity function that computes the value and returns either `{:ok, value}` or
      `{:error, reason}`.
    - `ttl_ms` ("time to live"): how long (in milliseconds) the value is stored before it is
      discarded if the value is not refreshed.
    - `refresh_interval_ms`: how often (in milliseconds) the function is recomputed and the new
      value stored. `refresh_interval` must be strictly smaller than `ttl`. After the value is
      refreshed, the `ttl_ms` counter is restarted.

  The value is stored only if `{:ok, value}` is returned by `function`. If `{:error, reason}` is
  returned, the value is not stored and `function` must be retried on the next run.
  """
  @spec register(
          GenServer.server(),
          atom(),
          Cache.value_function(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          :ok | {:error, :already_registered}
  def register(server, key, function, ttl_ms, refresh_interval_ms)
      when is_atom(key) and
             is_function(function, 0) and
             is_integer(ttl_ms) and ttl_ms > 0 and
             is_integer(refresh_interval_ms) and
             refresh_interval_ms < ttl_ms do
    GenServer.call(server, {:register, key, function, ttl_ms, refresh_interval_ms})
  end

  @doc """
  Get the value associated with `key`.

  ## Details

    - If the value for `key` is stored in the cache, the value is returned immediately.
    - If a recomputation of the function is in progress, the last stored value is returned.
    - If the value for `key` is not stored in the cache but a computation of the function
      associated with this `key` is in progress, wait up to `timeout` milliseconds. If the value
      is computed within this interval, the value is returned. If the computation does not finish
      in this interval, `{:error, :timeout}` is returned.
    - If `key` is not associated with any function, return `{:error, :not_registered}`
  """
  @spec get(GenServer.server(), atom(), non_neg_integer()) :: Cache.result()
  def get(server, key, timeout_ms \\ 30_000)
      when is_atom(key) and
             is_integer(timeout_ms) and timeout_ms > 0 do
    GenServer.call(server, {:get, key, timeout_ms})
  end

  # Server

  @impl GenServer
  def init(%State{} = state) do
    Process.flag(:trap_exit, true)

    children = [
      {Task.Supervisor, name: task_supervisor_name(state)}
    ]

    {:ok, _pid} =
      Supervisor.start_link(
        children,
        strategy: :one_for_one,
        name: supervisor_name(state)
      )

    {:ok, state}
  end

  @impl GenServer
  def handle_call(
        {:register, key, function, ttl_ms, refresh_interval_ms},
        _from,
        %State{} = state
      )
      when is_atom(key) and
             is_function(function, 0) and
             is_integer(ttl_ms) and ttl_ms > 0 and
             is_integer(refresh_interval_ms) and
             refresh_interval_ms < ttl_ms do
    if Map.has_key?(state.registrations_by_key, key) do
      {:reply, {:error, :already_registered}, state}
    else
      state =
        put_registration(
          state,
          key,
          Registration.new(
            function,
            ttl_ms,
            refresh_interval_ms
          )
        )

      send(self(), {:refresh, key})

      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call({:get, key, timeout_ms}, from, %State{} = state)
      when is_atom(key) and
             is_integer(timeout_ms) and timeout_ms > 0 do
    case state.registrations_by_key[key] do
      nil ->
        {:reply, {:error, :not_registered}, state}

      %Registration{refreshing: true, value: :none} = registration ->
        # If the value isn't available before this time has elapsed, we want to time out.
        timeout_reference = Process.send_after(self(), {:timeout, :get, key, from}, timeout_ms)

        # We'll store a reference to this call so we can respond to it later, once the value
        # becomes available.
        Map.put(
          registration.calls_awaiting_response,
          from,
          %CallAwaitingResponse{timeout_reference: timeout_reference}
        )
        |> Kernel.then(&%{registration | calls_awaiting_response: &1})
        |> Kernel.then(&put_registration(state, key, &1))
        |> Kernel.then(&{:noreply, &1})

      %Registration{value: {:ok, value}} ->
        {:reply, {:ok, value}, state}
    end
  end

  # Refreshes the value for a given key by calling the registered function.
  @impl GenServer
  def handle_info({:refresh, key}, %State{} = state)
      when is_atom(key) do
    case state.registrations_by_key[key] do
      nil ->
        state

      %Registration{} = registration ->
        task_reference =
          Task.Supervisor.async_nolink(
            task_supervisor_name(state),
            registration.value_function
          )

        # Refresh the value again after configured interval.
        Process.send_after(self(), {:refresh, key}, registration.refresh_interval_ms)

        state
        |> put_task_reference(task_reference, key)
        |> put_registration(key, %{registration | refreshing: true})
    end
    |> Kernel.then(&{:noreply, &1})
  end

  # Called when a value for the key still isn't available after the timeout interval has elapsed.
  @impl GenServer
  def handle_info({:timeout, :get, key, from}, %State{} = state) do
    GenServer.reply(from, {:error, :timeout})

    update_registration(state, key, fn %Registration{} = registration ->
      Map.delete(registration.calls_awaiting_response, from)
      |> Kernel.then(&%{registration | calls_awaiting_response: &1})
    end)
    |> Kernel.then(&{:noreply, &1})
  end

  # Called when a key hasn't been refreshed after the configured TTL has expired.
  @impl GenServer
  def handle_info({:timeout, :ttl, key}, %State{} = state) do
    update_registration(state, key, fn %Registration{} = registration ->
      %{registration | value: :none}
    end)
    |> Kernel.then(&{:noreply, &1})
  end

  # Called when a value-function task returns with a new value.
  @impl GenServer
  def handle_info({reference, result}, %State{} = state)
      when is_reference(reference) do
    case result do
      {:ok, value} ->
        case state.keys_by_task_reference[reference] do
          nil -> state
          key when is_atom(key) -> update_registration_value(state, key, value)
        end
        |> Kernel.then(&{:noreply, &1})

      _ ->
        {:noreply, state}
    end
  end

  # Called when a value-function task process exits.
  @impl GenServer
  def handle_info({:DOWN, reference, :process, _pid, _reason}, %State{} = state)
      when is_reference(reference) do
    drop_task_reference(state, reference)
    |> Kernel.then(&{:noreply, &1})
  end

  @impl GenServer
  def terminate(_reason, %State{} = state) do
    :ok = Supervisor.stop(supervisor_name(state))
  end

  @spec supervisor_name(State.t()) :: atom()
  defp supervisor_name(%State{} = state) do
    :"#{state.name}.Supervisor"
  end

  @spec task_supervisor_name(State.t()) :: atom()
  defp task_supervisor_name(%State{} = state) do
    :"#{state.name}.TaskSupervisor"
  end

  @spec put_task_reference(State.t(), Task.t(), atom()) :: State.t()
  defp put_task_reference(%State{} = state, %Task{ref: task_reference}, key) when is_atom(key) do
    Map.put(state.keys_by_task_reference, task_reference, key)
    |> Kernel.then(&%{state | keys_by_task_reference: &1})
  end

  @spec drop_task_reference(State.t(), reference()) :: State.t()
  defp drop_task_reference(%State{} = state, reference) when is_reference(reference) do
    Map.delete(state.keys_by_task_reference, reference)
    |> Kernel.then(&%{state | keys_by_task_reference: &1})
  end

  @spec put_registration(State.t(), atom(), Registration.t()) :: State.t()
  defp put_registration(%State{} = state, key, %Registration{} = registration) do
    Map.put(state.registrations_by_key, key, registration)
    |> Kernel.then(&%{state | registrations_by_key: &1})
  end

  @spec update_registration(State.t(), atom(), (Registration.t() -> Registration.t())) ::
          State.t()
  defp update_registration(%State{} = state, key, function)
       when is_atom(key) and is_function(function, 1) do
    Map.replace_lazy(state.registrations_by_key, key, function)
    |> Kernel.then(&%{state | registrations_by_key: &1})
  end

  @spec update_registration_value(State.t(), atom(), any()) :: State.t()
  defp update_registration_value(%State{} = state, key, value) do
    update_registration(state, key, fn %Registration{} = registration ->
      # There may be calls to `get` that are awaiting a response. We need to reply to each of them
      # now that a value is available.
      Enum.each(
        registration.calls_awaiting_response,
        fn {from, %CallAwaitingResponse{} = call} ->
          GenServer.reply(from, {:ok, value})
          Process.cancel_timer(call.timeout_reference)
        end
      )

      # Restart the TTL timer for this key now that a value's come in successfully.
      if not is_nil(registration.ttl_timer_reference) do
        Process.cancel_timer(registration.ttl_timer_reference)
      end

      ttl_timer_reference =
        Process.send_after(
          self(),
          {:timeout, :ttl, key},
          registration.ttl_ms
        )

      %{
        registration
        | refreshing: false,
          value: {:ok, value},
          calls_awaiting_response: %{},
          ttl_timer_reference: ttl_timer_reference
      }
    end)
  end
end
