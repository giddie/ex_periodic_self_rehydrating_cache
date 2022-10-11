defmodule Cache.Private.Registration do
  @moduledoc false

  alias __MODULE__, as: Self
  alias Cache.Private.CallAwaitingResponse

  @enforce_keys [
    :value_function,
    :value,
    :refreshing,
    :calls_awaiting_response,
    :ttl_ms,
    :ttl_timer_reference,
    :refresh_interval_ms
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          value_function: Cache.value_function(),
          value: :none | {:ok, any()},
          refreshing: boolean(),
          calls_awaiting_response: %{
            GenServer.from() => CallAwaitingResponse.t()
          },
          ttl_ms: non_neg_integer(),
          ttl_timer_reference: reference() | nil,
          refresh_interval_ms: non_neg_integer()
        }

  @spec new(Cache.value_function(), non_neg_integer(), non_neg_integer()) :: Self.t()
  def new(value_function, ttl_ms, refresh_interval_ms)
      when is_function(value_function, 0) and
             is_integer(ttl_ms) and
             is_integer(refresh_interval_ms) and
             refresh_interval_ms < ttl_ms do
    %Self{
      value_function: value_function,
      value: :none,
      refreshing: true,
      calls_awaiting_response: %{},
      ttl_ms: ttl_ms,
      ttl_timer_reference: nil,
      refresh_interval_ms: refresh_interval_ms
    }
  end
end
