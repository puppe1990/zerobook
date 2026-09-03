defmodule Zerobook do
  @moduledoc """
  Zerobook — a tamper-evident, double-entry ledger for Elixir.

  Pure-Elixir, zero dependencies. At its core:

    * `Zerobook.Entry` — one line of a transaction (account, integer amount,
      currency, optional description)
    * `Zerobook.Transaction` — a set of entries that must balance to zero in
      every currency
    * `Zerobook.Ledger` — an append-only chain of SHA-256 linked blocks that
      makes any past edit detectable

  ## Quick start

      alias Zerobook.{Ledger, Transaction, Entry}

      ledger =
        Ledger.new()
        |> Ledger.append!(Transaction.new("txn_1", [
          Entry.new("1000.cash", 10_000, "BRL", "deposit"),
          Entry.new("2000.revenue", -10_000, "BRL")
        ]))
        |> Ledger.append!(Transaction.new("txn_2", [
          Entry.new("3000.expense", 2_500, "BRL", "hosting"),
          Entry.new("1000.cash", -2_500, "BRL")
        ]))

      Ledger.verify!(ledger)                    # => :ok
      Ledger.balance_of(ledger, "1000.cash", "BRL")  # => 7500

  ## Why integers?

  Monetary values are integers to avoid floating point drift. Use the
  smallest unit of your currency (cents for BRL/USD, attos for crypto,
  credits as plain integers). It is your job to be consistent.

  ## Tamper evidence

  Each block stores the SHA-256 of its content plus the hash of the previous
  block. `Zerobook.Ledger.verify/1` recomputes every link; any change to a
  past transaction, or any reordering/insertion/deletion, breaks the chain
  and is reported with the offending block index.

  Ledger state is plain immutable data (blocks are structs with `prev_hash`
  and `hash` fields), so persistence is trivial: store blocks in SQLite,
  Postgres (jsonb) or ETS and rebuild the ledger by appending them in order.
  """

  alias Zerobook.{Entry, Ledger, Transaction}

  @doc """
  Shorthand for `Zerobook.Entry.new/4`.
  """
  defdelegate entry(account, amount, currency, description \\ nil), to: Entry, as: :new

  @doc """
  Shorthand for `Zerobook.Transaction.new/3`.
  """
  defdelegate transaction(id, entries, opts \\ []), to: Transaction, as: :new

  @doc """
  Shorthand for `Zerobook.Ledger.new/0`.
  """
  defdelegate new_ledger(), to: Ledger, as: :new

  @doc """
  Shorthand for `Zerobook.Ledger.append/2`.
  """
  defdelegate append(ledger, transaction), to: Ledger

  @doc """
  Shorthand for `Zerobook.Ledger.verify/1`.
  """
  defdelegate verify(ledger), to: Ledger

  @doc """
  Shorthand for `Zerobook.Ledger.balance_of/3`.
  """
  defdelegate balance_of(ledger, account, currency), to: Ledger
end
