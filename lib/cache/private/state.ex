defmodule Cache.Private.State do
  @moduledoc false

  alias __MODULE__, as: Self
  alias Cache.Private.Registration

  @enforce_keys [
    :registrations_by_key
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          registrations_by_key: %{atom() => Registration.t()}
        }

  @spec new() :: Self.t()
  def new() do
    %Self{
      registrations_by_key: %{}
    }
  end
end
