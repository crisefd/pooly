defmodule Pooly do
  @moduledoc """
    Main module of the Application. 
  """

  use Application

  @timeout 5_000

  @pool_config [
    [name: "Pool1",
     mfa: {SampleWorker, :start_link, []},
     size: 2,
     max_overflow: 1],
    [name: "Pool2",
     mfa: {SampleWorker, :start_link, []}, 
     size: 3,
     max_overflow: 0],
    [name: "Pool3",
     mfa: {SampleWorker, :start_link, []},
     size: 4,
     max_overflow: 0]
  ]

  def start(_type, _args) do
    start_pools(@pool_config)
  end

  def start_pools(pool_config) do
    Pooly.Supervisor.start_link(pool_config)
  end

  def checkout(pool_name, block \\ true, timeout \\ @timeout) do
    Pooly.Server.checkout(pool_name, block, timeout)
  end

  def checkin(pool_name, worker_pid) do
    Pooly.Server.checkin(pool_name, worker_pid)
  end

  def status(pool_name) do
    Pooly.Server.status(pool_name)
  end

  def transaction(pool_name, fun, timeout) do
    Pooly.Server.transaction(pool_name, fun, timeout)
  end

end
