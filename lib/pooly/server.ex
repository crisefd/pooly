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

  def status(pool_name) do
    GenServer.call(:"#{pool_name}Server", :status)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(
      :"#{pool_name}Server",
      {:checkin, worker_pid}
    )
  end

  def checkout(pool_name) do
    GenServer.call(:"#{pool_name}Server", :checkout)
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
