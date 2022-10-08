defmodule Cache.Private.Registration do
  @moduledoc false

  alias __MODULE__, as: Self

  @enforce_keys [
    :value_function
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          value_function: Cache.value_function()
        }
end
