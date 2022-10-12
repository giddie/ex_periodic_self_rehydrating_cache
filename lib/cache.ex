defmodule Cache do
  @moduledoc """
  Periodic Self-Rehydrating Cache

  This is a singleton instance of `Cache.Server` available for convenience.

  ## Usage

      iex> Cache.register(
      ...>   :my_key,
      ...>   fn -> {:ok, "My Value"} end,
      ...>   10_000,
      ...>   1_000
      ...> )
      :ok
      iex> Cache.get(:my_key)
      {:ok, "My Value"}
  """

  alias __MODULE__, as: Self
  alias Self.Server

  @type value_function :: (() -> {:ok, any()} | {:error, any()})
  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  @doc """
  Clears the cache and starts from scratch.
  """
  @spec clear() :: :ok
  def clear() do
    Supervisor.terminate_child(Cache.Application.Supervisor, Server)
    {:ok, _pid} = Supervisor.restart_child(Cache.Application.Supervisor, Server)

    :ok
  end

  @doc """
  Registers a function that will be computed periodically to update the cache.

  See `Cache.Server.register/5` for argument details.
  """
  @spec register(
          key :: any(),
          function :: value_function(),
          ttl_ms :: non_neg_integer(),
          refresh_interval_ms :: non_neg_integer()
        ) :: :ok | {:error, :already_registered}
  def register(key, function, ttl_ms, refresh_interval_ms)
      when is_atom(key) and
             is_function(function, 0) and
             is_integer(ttl_ms) and ttl_ms > 0 and
             is_integer(refresh_interval_ms) and
             refresh_interval_ms < ttl_ms do
    Server.register(Server, key, function, ttl_ms, refresh_interval_ms)
  end

  @doc """
  Get the value associated with `key`.

  See `Cache.Server.get/3` for details.
  """
  @spec get(any(), non_neg_integer()) :: result
  def get(key, timeout_ms \\ 30_000)
      when is_integer(timeout_ms) and timeout_ms > 0 do
    Server.get(Server, key, timeout_ms)
  end
end
