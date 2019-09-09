defmodule SampleWorker do
   @moduledoc """
     Does the grunt work. Leaf node in the supervision tree
  """
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def init(init_arg) do
    {:ok, init_arg}
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end
end
