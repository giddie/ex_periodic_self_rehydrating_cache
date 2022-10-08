defmodule Cache.Private.Registration do
  @moduledoc false

  alias __MODULE__, as: Self

  @enforce_keys [
    :value_function,
    :value,
    :refreshing,
    :calls_awaiting_response
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          value_function: Cache.value_function(),
          value: any(),
          refreshing: boolean(),
          calls_awaiting_response: [GenServer.from()]
        }

  @spec new(Cache.value_function()) :: Self.t()
  def new(value_function)
      when is_function(value_function, 0) do
    %Self{
      value_function: value_function,
      value: :none,
      refreshing: false,
      calls_awaiting_response: []
    }
  end
end
