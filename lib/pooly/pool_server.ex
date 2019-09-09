defmodule Pooly.PoolServer do
  @moduledoc """
    Kicks-starts and manages state for Pooly.PoolSupervisor
  """
  
  use GenServer
  import Supervisor.Spec

  #  API

  def start_link(pool_supervisor, pool_config) do
    GenServer.start_link(
      __MODULE__,
      [pool_supervisor, pool_config],
      name: name(pool_config[:name])
    )
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

  def checkout(pool_name) do
    GenServer.call(name(pool_name), :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  # GenServer callbacks

  def init([pool_supervisor, pool_config]) when is_pid(pool_supervisor) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    init(
      pool_config,
      %State{pool_sup: pool_supervisor, monitors: monitors}
    )
  end
	
  def init([{:name, name} | rest], state) do
    init(rest, %{state | name: name})
  end

  def init([{:mfa, mfa} | rest], state) do
    init(rest, %{state | mfa: mfa})
  end

  def init([{:size, size} | rest], state) do
    init(rest, %{state | size: size})
  end

  def init([], state) do
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  def init([_ | rest], state) do
    init(rest, state)
  end

  def terminate(_reason, _state), do: :ok

  def handle_info(
        {:DOWN, ref, _, _, _},
        state = %State{monitors: monitors, workers: workers}
      ) do
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        true = :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid | workers]}
        {:noreply, new_state}

      [] ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:EXIT, worker_supervisor, reason},
        state = %State{worker_sup: worker_supervisor}
      ) do
    {:stop, reason, state}
  end

  def handle_info(
        {:EXIT, from_pid, _reason},
        state = %State{monitors: monitors, workers: workers, pool_sup: pool_sup}
      ) do
    case :ets.lookup(monitors, from_pid) do
      [{_pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, from_pid)
        new_state = %{state | workers: [new_worker(pool_sup) | workers]}
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        :start_worker_supervisor,
        state = %State{pool_sup: pool_sup, name: name, mfa: mfa, size: size}
      ) do
    {:ok, worker_sup} =
      Supervisor.start_child(
        pool_sup,
        supervisor_spec(name, mfa)
      )

    workers = prepopulate(size, worker_sup)
    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  def handle_cast(
        {:checkin, worker_pid},
        state = %State{workers: workers, monitors: monitors}
      ) do
    case :ets.lookup(monitors, worker_pid) do
      [{_pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, worker_pid)
        {:noreply, %{state | workers: [worker_pid | workers]}}

      [] ->
        {:noreply, state}
    end
  end

  def handle_call(
        :status,
        _from,
        state = %State{workers: workers, monitors: monitors}
      ) do
    {:reply, {length(workers), :ets.info(monitors, :size)}, state}
  end

  def handle_call(
        :checkout,
        {from_pid, _ref},
        state = %State{workers: workers, monitors: monitors}
      ) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] ->
        {:reply, :noproc, state}
    end
  end

  # Private functions

  defp name(pool_name), do: :"#{pool_name}Server"

  defp prepopulate(size, supervisor) do
    prepopulate(size, supervisor, [])
  end

  defp prepopulate(size, _supervisor, workers) when size == 0 do
    workers
  end

  defp prepopulate(size, supervisor, workers) do
    prepopulate(
      size - 1,
      supervisor,
      [new_worker(supervisor) | workers]
    )
  end

  defp new_worker(supervisor) do
    {:ok, worker} = Supervisor.start_child(supervisor, [[]])
    worker
  end

  defp supervisor_spec(name, mfa) do
    opts = [id: name <> "WorkerSupervisor", restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [self(), mfa], opts)
  end
end
