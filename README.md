# Zerobook

A tamper-evident, double-entry ledger for Elixir. Pure Elixir, zero
dependencies.

Every transaction must balance to zero in every currency, and transactions
are chained with SHA-256 links — so any edit to a past transaction, or any
reordering or deletion of a block, is detected when you verify the chain.

## Features

- **Double-entry by construction** — a transaction is rejected unless its
  entries sum to zero per currency
- **Tamper-evident** — hash-chained blocks; `verify/1` detects edits,
  reordering, insertion and deletion
- **Multi-currency** — transactions may mix currencies; each currency must
  balance independently
- **Integers only** — use cents/attos; no floating point drift, ever
- **In-memory, plain data** — persist blocks anywhere (SQLite, Postgres,
  ETS) and rebuild the ledger by appending them in order

## Installation

Add `zerobook` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:zerobook, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
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

Ledger.verify!(ledger)                        # => :ok
Ledger.balance_of(ledger, "1000.cash", "BRL") # => 7500
```

Sign convention: a **positive** amount debits an account (money flows in),
a **negative** amount credits it (money flows out). Keep it consistent and
use the smallest unit of your currency (cents for BRL/USD, attos for
crypto, plain integers for credits/points).

### Error handling

`Ledger.append/2` returns tagged tuples instead of raising:

```elixir
case Ledger.append(ledger, tx) do
  {:ok, ledger} -> ledger
  {:error, {:unbalanced, currency, total}} -> # transaction did not sum to zero
  {:error, {:duplicate_transaction, id}} ->   # id already in the chain
end
```

### Verifying the chain

`Ledger.verify/1` returns `:ok` or an error pinpointing the first broken
block (0-based position in the chain):

```elixir
{:error, {:bad_hash, 3}}        # block 3 was edited after being written
{:error, {:broken_link, 1}}     # block 1 does not point to block 0's hash
{:error, {:unbalanced_tx, 2}}   # a transaction no longer balances
```

### Queries

```elixir
Ledger.balance_of(ledger, "1000.cash", "BRL")     # running balance
Ledger.statements(ledger, "1000.cash")            # [{txn, entry}, ...]
Ledger.blocks(ledger)                             # full chain, oldest first
Ledger.last_block(ledger)                         # latest block or nil
```

### Persistence

Ledger and block structs are plain serializable data:

```elixir
block = Ledger.last_block(ledger)
%Zerobook.Block{
  index: 1,
  timestamp: ~U[2026-09-03 12:00:00Z],
  transaction: %Zerobook.Transaction{...},
  prev_hash: <<...>>,  # SHA-256 of the previous block
  hash: <<...>>        # SHA-256 of this block's content
}
```

Store the blocks (e.g. as JSON in Postgres or rows in SQLite) and replay
them into a fresh ledger on startup.

## Design notes

- Each block hashes its index, timestamp, transaction id, reference,
  description and every entry — a change to any of them breaks the chain.
- `timestamp` is informational for now: append order defines the chain.
  For a production ledger, persist your own transaction id uniqueness and
  ordering rules around your storage engine.

## License

MIT — see [LICENSE](LICENSE).
