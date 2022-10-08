defmodule Cache.Private.State do
  @moduledoc false

  alias __MODULE__, as: Self
  alias Cache.Private.Registration

  @enforce_keys [
    :name,
    :registrations_by_key,
    :keys_by_task_reference
  ]
  defstruct @enforce_keys

  @type t :: %Self{
          name: atom(),
          registrations_by_key: %{atom() => Registration.t()},
          keys_by_task_reference: %{reference() => atom()}
        }

  @spec new(atom()) :: Self.t()
  def new(name) when is_atom(name) do
    %Self{
      name: name,
      registrations_by_key: %{},
      keys_by_task_reference: %{}
    }
  end
end
