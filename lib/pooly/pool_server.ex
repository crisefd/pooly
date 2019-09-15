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

  def checkout(pool_name, block, timeout) do
    GenServer.call(name(pool_name), {:checkout, block}, timeout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  # GenServer callbacks

  def init([pool_supervisor, pool_config]) when is_pid(pool_supervisor) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])
    waiting  = :queue.new
    init(
      pool_config,
      %State{pool_sup: pool_supervisor,
             monitors: monitors,
             overflow: 0,
             waiting: waiting}
    )
  end

  def init([{:max_overflow, max_overflow} | rest], state) do
    init(rest, %{ state | max_overflow: max_overflow })
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
        state = %State{monitors: monitors, workers: _, pool_sup: _}
      ) do
    case :ets.lookup(monitors, from_pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_worker_exit(state)
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
        state = %State{workers: _,
                       monitors: monitors,
                       overflow: _}
      ) do
    case :ets.lookup(monitors, worker_pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, pid)
        new_state = handle_checkin(pid, state)
        {:noreply, new_state}

      [] ->
        {:noreply, state}
    end
  end

  def handle_call(
        :status,
        _from,
        state = %State{workers: workers, monitors: monitors}
      ) do
    {:reply,
      {state_name(state), length(workers), :ets.info(monitors, :size)},
      state}
  end

  def handle_call(
        {:checkout, block},
        {from_pid, _ref} = from,
        state = %State{workers: workers,
                       monitors: monitors,
                       overflow: overflow,
                       waiting: waiting,
                       worker_sup: worker_sup,
                       max_overflow: max_overflow}
      ) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}
      [] when max_overflow > 0 and overflow < max_overflow ->
        {worker, ref} = new_worker(worker_sup, from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{ state | overflow: overflow + 1 }}
      [] when block ->
        ref = Process.monitor(from_pid)
        new_waiting = :queue.in({from, ref}, waiting)
        {:noreply, %{state | waiting: new_waiting}, :infinity}
      [] ->
        {:reply, :full, state}
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

  defp new_worker(worker_sup, from_pid) do
    pid = new_worker(worker_sup)
    ref = Process.monitor(from_pid)
    {pid, ref}
  end

  defp supervisor_spec(name, mfa) do
    opts = [id: name <> "WorkerSupervisor", restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [self(), mfa], opts)
  end

   defp dismiss_worker(supervisor, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(supervisor, pid)
  end


  def handle_checkin(pid,
                      %{worker_sup: worker_sup,
                        workers: workers,
                        monitors: monitors,
                        waiting: waiting,
                        overflow: overflow} = state) do
    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        true = :ets.insert(monitors, {pid, ref})
        GenServer.reply(from, pid)
        %{state | waiting: left}
      {:empty, empty} when overflow > 0 ->
        :ok = dismiss_worker(worker_sup, pid)
        %{state | waiting: empty, overflow: overflow - 1}
      {:empty, empty} ->
        %{state | waiting: empty, workers: [ pid | workers ], overflow: 0}
    end
  end

  defp handle_worker_exit( %State{worker_sup: worker_sup,
                                  workers:  workers,
                                  monitors: monitors,
                                  waiting: waiting,
                                  overflow: overflow} = state)  do
    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        new_worker = new_worker(worker_sup)
        true = :ets.insert(monitors, {new_worker, ref})
        GenServer.reply(from, new_worker)
        %{state | waiting: left}
      {:empty, empty} when overflow > 0 ->
        %{state | overflow: overflow - 1, waiting: empty}
      {:empty, empty} ->
        workers = [new_worker(worker_sup) | workers]
        %{state | workers: workers, waiting: empty}
    end
  end

  defp state_name(%State{overflow: overflow,
                         max_overflow: max_overflow,
                         workers: workers}) when overflow < 1 do
    state_name(workers, max_overflow)
  end

  defp state_name(%State{overflow: max_overflow,
                         max_overflow: max_overflow}) do
    :full
  end

  defp state_name(_state), do: :overflow

  defp state_name([], max_overflow) when max_overflow < 1, do: :full

  defp state_name([], _max_overflow), do: :overflow

  defp state_name(_workers, _max_overflow), do: :ready


end
