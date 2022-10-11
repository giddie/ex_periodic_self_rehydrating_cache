defmodule Cache.Application do
  @moduledoc """
  Starts a default Cache server.
  """

  alias __MODULE__, as: Self

  @behaviour Application

  @impl Application
  def start(_type, _args) do
    children = [
      Cache.Server
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Self.Supervisor)
  end

  @impl Application
  def stop(_state) do
  end
end
