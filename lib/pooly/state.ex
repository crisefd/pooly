  defmodule State do
    @moduledoc """
      The server state
    """
    defstruct pool_sup: nil,
    worker_sup: nil,
    monitors: nil,
    monitors: nil,
    size: nil,
    workers: nil,
    name: nil,
    mfa: nil,
    waiting: nil,
    overflow: nil,
    max_overflow: nil
  end
