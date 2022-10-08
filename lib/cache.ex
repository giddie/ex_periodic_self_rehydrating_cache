defmodule Cache do
  @moduledoc """
  Periodic Self-Rehydrating Cache
  """

  @type result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :not_registered}

  @doc """
  Registers a function that will be computed periodically to update the cache.

  Arguments:
    - `fun`: a 0-arity function that computes the value and returns either `{:ok, value}` or
      `{:error, reason}`.
    - `key`: associated with the function and is used to retrieve the stored value.
    - `ttl_ms` ("time to live"): how long (in milliseconds) the value is stored before it is
      discarded if the value is not refreshed.
    - `refresh_interval_ms`: how often (in milliseconds) the function is recomputed and the new
      value stored. `refresh_interval` must be strictly smaller than `ttl`. After the value is
      refreshed, the `ttl_ms` counter is restarted.

  The value is stored only if `{:ok, value}` is returned by `fun`. If `{:error, reason}` is
  returned, the value is not stored and `fun` must be retried on the next run.
  """
  @spec register_function(
          fun :: (() -> {:ok, any()} | {:error, any()}),
          key :: any(),
          ttl :: non_neg_integer(),
          refresh_interval :: non_neg_integer()
        ) :: :ok | {:error, :already_registered}
  def register_function(fun, _key, ttl_ms, refresh_interval_ms)
      when is_function(fun, 0) and is_integer(ttl_ms) and ttl_ms > 0 and
             is_integer(refresh_interval_ms) and
             refresh_interval_ms < ttl_ms do
    :ok
  end

  @doc """
  Get the value associated with `key`.

  Details:
    - If the value for `key` is stored in the cache, the value is returned immediately.
    - If a recomputation of the function is in progress, the last stored value is returned.
    - If the value for `key` is not stored in the cache but a computation of the function
      associated with this `key` is in progress, wait up to `timeout` milliseconds. If the value
      is computed within this interval, the value is returned. If the computation does not finish
      in this interval, `{:error, :timeout}` is returned.
    - If `key` is not associated with any function, return `{:error, :not_registered}`
  """
  @spec get(any(), non_neg_integer()) :: result
  def get(_key, timeout \\ 30_000)
      when is_integer(timeout) and timeout > 0 do
    {:error, :not_registered}
  end
end
