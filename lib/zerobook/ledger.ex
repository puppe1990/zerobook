defmodule Zerobook.Ledger do
  @moduledoc """
  A tamper-evident, double-entry ledger.

  The ledger is a linear chain of `Zerobook.Block`s; each block holds the
  SHA-256 of its own content plus the hash of the previous block. Any edit
  to a past transaction — or a reordering, insertion or deletion of a
  block — breaks every subsequent hash, so tampering is detectable by
  re-verifying the chain.

  ## Usage

      ledger =
        Zerobook.Ledger.new()
        |> Zerobook.Ledger.append!(Zerobook.Transaction.new("txn_1", [
          Zerobook.Entry.new("1000.cash", 1_000, "BRL"),
          Zerobook.Entry.new("2000.revenue", -1_000, "BRL")
        ]))

      Zerobook.Ledger.verify!(ledger) # => :ok

  Ledger state is immutable data (`%Zerobook.Ledger{blocks: [...]}`); each
  block is plain data with `prev_hash`/`hash` links, so persistence is up to
  the caller — store blocks in SQLite/Postgres (jsonb) and rebuild the
  ledger by appending them in order.
  """

  alias Zerobook.{Block, Entry, Transaction}

  defstruct index: 0, blocks: [], last_hash: <<0::256>>

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          blocks: [Block.t()],
          last_hash: binary()
        }

  @type result :: {:ok, t()} | {:error, term()}

  @genesis_prev_hash <<0::256>>

  @doc "Creates an empty ledger."
  def new, do: %__MODULE__{index: 0, blocks: [], last_hash: @genesis_prev_hash}

  @doc """
  Validates a transaction and appends it as a new block, returning
  `{:ok, ledger}`.

  Rejects unbalanced transactions and duplicate transaction ids.
  """
  def append(ledger, %Transaction{} = tx) do
    with :ok <- Transaction.validate(tx),
         :ok <- ensure_unique_id(ledger, tx) do
      block = build_block(ledger.last_hash, ledger.index, tx)

      {:ok,
       %{
         ledger
         | index: ledger.index + 1,
           blocks: ledger.blocks ++ [block],
           last_hash: block.hash
       }}
    end
  end

  @doc "Appends and unwraps: returns the updated ledger or raises."
  def append!(ledger, tx) do
    case append(ledger, tx) do
      {:ok, updated} -> updated
      {:error, reason} -> raise ArgumentError, "zerobook: #{inspect(reason)}"
    end
  end

  @doc """
  Verifies the whole chain: structural hashes and balanced transactions.

  Returns `:ok` or `{:error, reason}` where reason is one of (positions
  are 0-based indexes into the block list):

    * `{:bad_hash, position}` — the stored hash of the block at `position`
      does not match its recomputed content hash (tamper detected)
    * `{:broken_link, position}` — block at `position` does not reference
      the hash of the previous block (reorder/insertion/deletion detected)
    * `{:unbalanced_tx, position}` — transaction at `position` no longer
      sums to zero in every currency

  """
  def verify(%__MODULE__{blocks: []}), do: :ok

  def verify(%__MODULE__{} = ledger) do
    genesis = @genesis_prev_hash

    result =
      ledger.blocks
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, genesis}, fn {block, position}, {:ok, prev} ->
        cond do
          block.hash != content_hash(block) ->
            {:halt, {:error, {:bad_hash, position}}}

          block.prev_hash != prev ->
            {:halt, {:error, {:broken_link, position}}}

          Transaction.validate(block.transaction) != :ok ->
            {:halt, {:error, {:unbalanced_tx, position}}}

          true ->
            {:cont, {:ok, block.hash}}
        end
      end)

    case result do
      {:ok, _last_hash} -> :ok
      error -> error
    end
  end

  @doc "Verifies and unwraps: returns `:ok` or raises."
  def verify!(ledger) do
    case verify(ledger) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "zerobook: invalid chain: #{inspect(reason)}"
    end
  end

  @doc "Returns the list of blocks, oldest first."
  def blocks(%__MODULE__{} = ledger), do: ledger.blocks

  @doc "Returns the last block, or `nil` on an empty ledger."
  def last_block(%__MODULE__{blocks: []}), do: nil
  def last_block(%__MODULE__{} = ledger), do: List.last(ledger.blocks)

  @doc """
  Computes the running balance of `account` in `currency`.

  ## Examples

      iex> ledger = Zerobook.Ledger.new() |> Zerobook.Ledger.append!(Zerobook.Transaction.new("t1", [
      ...>   Zerobook.Entry.new("1000.cash", 1_000, "BRL"),
      ...>   Zerobook.Entry.new("2000.revenue", -1_000, "BRL")
      ...> ]))
      iex> Zerobook.Ledger.balance_of(ledger, "1000.cash", "BRL")
      1000

  """
  def balance_of(%__MODULE__{} = ledger, account, currency) do
    Enum.reduce(ledger.blocks, 0, fn block, acc ->
      Enum.reduce(block.transaction.entries, acc, fn e, inner ->
        if e.account == account and e.currency == currency do
          inner + e.amount
        else
          inner
        end
      end)
    end)
  end

  @doc """
  Returns all postings touching `account` as
  `{transaction, entry}` pairs, oldest first.
  """
  def statements(%__MODULE__{} = ledger, account) do
    for block <- ledger.blocks,
        entry <- block.transaction.entries,
        entry.account == account,
        do: {block.transaction, entry}
  end

  # --- internals ---

  defp ensure_unique_id(%__MODULE__{blocks: blocks}, tx) do
    if Enum.any?(blocks, &(&1.transaction.id == tx.id)) do
      {:error, {:duplicate_transaction, tx.id}}
    else
      :ok
    end
  end

  defp build_block(prev_hash, index, tx) do
    %Block{
      index: index,
      timestamp: tx.timestamp,
      transaction: tx,
      prev_hash: prev_hash,
      hash:
        content_hash(%Block{
          index: index,
          timestamp: tx.timestamp,
          transaction: tx,
          prev_hash: prev_hash
        })
    }
  end

  defp content_hash(block) do
    :crypto.hash(:sha256, content_bin(block))
  end

  defp content_bin(block) do
    tx = block.transaction

    tx_bin =
      tx.entries
      |> Enum.map(&Entry.canonical/1)
      |> Enum.join(";")

    [
      Integer.to_string(block.index),
      DateTime.to_iso8601(block.timestamp),
      tx.id,
      tx.reference || "",
      tx.description || "",
      tx_bin
    ]
    |> Enum.join("|")
  end
end
