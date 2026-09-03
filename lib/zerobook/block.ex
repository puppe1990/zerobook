defmodule Zerobook.Block do
  @moduledoc """
  A block in a `Zerobook.Ledger` chain.

  Holds one transaction plus the SHA-256 of its own canonical content
  (`hash`) and the `prev_hash` of the previous block — the two fields that
  make the chain tamper-evident.
  """

  alias Zerobook.Transaction

  defstruct [:index, :timestamp, :transaction, :prev_hash, :hash]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          timestamp: DateTime.t(),
          transaction: Transaction.t(),
          prev_hash: binary(),
          hash: binary()
        }
end
