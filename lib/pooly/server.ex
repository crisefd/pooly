defmodule Pooly.Server do
  @moduledoc """
    Kicks-starts Pooly.PoolsSupervisor
   """

  use GenServer
  import Supervisor.Spec


  # API

  def start_link(pools_config) do
    GenServer.start_link(
      __MODULE__,
      pools_config,
      name: __MODULE__
    )
  end

  def transaction(pool_name, fun, timeout) do
    worker = checkout(pool_name, true, timeout)
    try do
      fun.(worker)
      after
        checkin(pool_name, worker)
    end
  end

  def status(pool_name) do
    Pooly.PoolServer.status(pool_name)
  end

  def checkin(pool_name, worker_pid) do
    Pooly.PoolServer.checkin(pool_name, worker_pid)
  end

  def checkout(pool_name, block, timeout) do
    Pooly.PoolServer.checkout(pool_name, block, timeout)
  end


  # GenServer callbacks

  def init(pools_config) do
    send_start_pool_signal = fn pool_config ->
      send(self(), {:start_pool, pool_config})
    end
    pools_config |> Enum.each(send_start_pool_signal)
    {:ok, pools_config}
  end

  def handle_info({:start_pool, pool_config}, state) do
    {:ok, _pool_supervisor} =
      Supervisor.start_child(
        Pooly.PoolsSupervisor,
        supervisor_spec(pool_config)
      )

    {:noreply, state}
  end

  # Private functions

  defp supervisor_spec(pool_config) do
    opts = [id: :"#{pool_config[:name]}Supervisor"]
    supervisor(Pooly.PoolSupervisor, [pool_config], opts)
  end

end
