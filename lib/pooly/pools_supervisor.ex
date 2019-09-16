defmodule Pooly.PoolsSupervisor do
  @moduledoc """
    Supervisor for Pooly.PoolSupervisor 
  """

  use Supervisor

  # API

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  # GenServer callbacks

  def init(_) do
    opts = [
      strategy: :one_for_one
    ]
    supervise([], opts)
  end
end