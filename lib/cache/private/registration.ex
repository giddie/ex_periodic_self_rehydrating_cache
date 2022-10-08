defmodule Cache.Private.Registration do
  @moduledoc false

  alias __MODULE__, as: Self

  @enforce_keys [
    :value_function,
    :value
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          value_function: Cache.value_function(),
          value: any()
        }
end
