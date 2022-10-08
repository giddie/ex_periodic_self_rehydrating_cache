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
    GenServer.start_link(Self, State.new(), name: name)
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
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get, key}, _from, %State{} = state) when is_atom(key) do
    case state.registrations_by_key[key] do
      nil -> {:error, :not_registered}
      %Registration{value: value} -> value
    end
    |> Kernel.then(fn value ->
      {:reply, value, state}
    end)
  end

  @impl GenServer
  def handle_call({:register, key, function}, _from, %State{} = state)
      when is_atom(key) and is_function(function, 0) do
    if Map.has_key?(state.registrations_by_key, key) do
      {:reply, {:error, :already_registered}, state}
    else
      registrations_by_key =
        Map.put(state.registrations_by_key, key, %Registration{
          value_function: function,
          value: function.()
        })

      state = %{state | registrations_by_key: registrations_by_key}

      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast({:store, key, value}, %State{} = state) do
    state = Map.put(state, key, value)
    {:noreply, state}
  end
end
