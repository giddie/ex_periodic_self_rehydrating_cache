defmodule Cache.Server do
  @moduledoc """
  GenServer implementation for a Periodic Self-Rehydrating Cache
  """

  alias __MODULE__, as: Self
  alias Cache.Private.State
  alias Cache.Private.Registration

  use GenServer

  # Client

  @spec start_link(atom()) :: {:ok, pid()}
  def start_link(name \\ Self) when is_atom(name) do
    GenServer.start_link(Self, State.new(name), name: name)
  end

  @spec register(GenServer.server(), atom(), Cache.value_function()) ::
          :ok | {:error, :already_registered}
  def register(server, key, function)
      when is_atom(key) and
             is_function(function, 0) do
    GenServer.call(server, {:register, key, function})
  end

  @spec get(GenServer.server(), atom()) :: Cache.result()
  def get(server, key) when is_atom(key) do
    GenServer.call(server, {:get, key})
  end

  # Server

  @impl GenServer
  def init(%State{} = state) do
    children = [
      {Task.Supervisor, name: task_supervisor_name(state)}
    ]

    {:ok, _pid} = Supervisor.start_link(children, strategy: :one_for_one)
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get, key}, from, %State{} = state) when is_atom(key) do
    case state.registrations_by_key[key] do
      nil ->
        {:reply, {:error, :not_registered}, state}

      %Registration{refreshing: true} = registration ->
        [from | registration.calls_awaiting_response]
        |> Kernel.then(&%{registration | calls_awaiting_response: &1})
        |> Kernel.then(&put_registration(state, key, &1))
        |> Kernel.then(&{:noreply, &1})

      %Registration{value: value} ->
        {:reply, value, state}
    end
  end

  @impl GenServer
  def handle_call({:register, key, function}, _from, %State{} = state)
      when is_atom(key) and is_function(function, 0) do
    if Map.has_key?(state.registrations_by_key, key) do
      {:reply, {:error, :already_registered}, state}
    else
      state = put_registration(state, key, Registration.new(function))
      send(self(), {:refresh, key})

      {:reply, :ok, state}
    end
  end

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

        state
        |> put_task_reference(task_reference, key)
        |> put_registration(key, %{registration | refreshing: true})
    end
    |> Kernel.then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info({reference, value}, %State{} = state)
      when is_reference(reference) do
    case state.keys_by_task_reference[reference] do
      nil -> state
      key when is_atom(key) -> update_registration_value(state, key, value)
    end
    |> Kernel.then(&{:noreply, &1})
  end

  @impl GenServer
  def handle_info({:DOWN, reference, :process, _pid, :normal}, %State{} = state)
      when is_reference(reference) do
    drop_task_reference(state, reference)
    |> Kernel.then(&{:noreply, &1})
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
      Enum.each(
        registration.calls_awaiting_response,
        &GenServer.reply(&1, value)
      )

      %{
        registration
        | refreshing: false,
          value: value,
          calls_awaiting_response: []
      }
    end)
  end
end
