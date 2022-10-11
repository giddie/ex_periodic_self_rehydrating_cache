defmodule Cache.Private.CallAwaitingResponse do
  @moduledoc false

  alias __MODULE__, as: Self

  @enforce_keys [
    :timeout_reference
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          timeout_reference: reference()
        }
end
