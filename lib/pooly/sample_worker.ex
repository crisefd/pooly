defmodule SampleWorker do
   @moduledoc """
     Does the grunt work. Leaf node in the supervision tree
  """
  use GenServer

  # API

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def work_for(pid, duration) do
    GenServer.cast(pid, {:work_for, duration})
  end

   def stop(pid) do
    GenServer.call(pid, :stop)
   end

  # GenServer callbacks

  def init(init_arg) do
    {:ok, init_arg}
  end

  def handle_cast({:work_for, duration}, state) do
    :timer.sleep(duration)
    {:stop, :normal, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end
end