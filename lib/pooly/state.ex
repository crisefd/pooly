defmodule State do
  @moduledoc """
    The state of the server
  """
  defstruct sup: nil,
            worker_sup: nil,
            size: nil,
            workers: nil,
            mfa: nil,
            monitors: nil,
            name: nil,
            pool_sup: nil
end
