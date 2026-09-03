defmodule Zerobook.Transaction do
  @moduledoc """
  A transaction: a set of `Zerobook.Entry` lines that must balance to zero
  per currency (double-entry accounting).

  Transactions are immutable, carry a UTC `timestamp`, an optional external
  `reference` (e.g. your own order/payment id — uniqueness is enforced by the
  ledger, not here), and an optional human `description`.
  """

  alias Zerobook.Entry

  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: DateTime.t(),
          reference: String.t() | nil,
          description: String.t() | nil,
          entries: [Entry.t()]
        }

  defstruct [:id, :timestamp, :reference, :description, entries: []]

  @doc """
  Creates a transaction, validating that entries balance to zero in every
  currency.

  ## Examples

      iex> tx = Zerobook.Transaction.new("txn_1", [
      ...>   Zerobook.Entry.new("1000.cash", 1_000, "BRL"),
      ...>   Zerobook.Entry.new("2000.revenue", -1_000, "BRL")
      ...> ])
      iex> tx.id
      "txn_1"

  """
  def new(id, entries, opts \\ []) when is_binary(id) and is_list(entries) do
    timestamp = Keyword.get(opts, :timestamp) || DateTime.utc_now()
    reference = Keyword.get(opts, :reference)
    description = Keyword.get(opts, :description)

    %__MODULE__{
      id: id,
      timestamp: timestamp,
      reference: reference,
      description: description,
      entries: entries
    }
  end

  @doc """
  Returns `:ok` when the transaction balances (sums to zero in every
  currency), otherwise `{:error, reason}` with the offending balances.
  """
  def validate(%__MODULE__{} = tx) do
    balances =
      Enum.reduce(tx.entries, %{}, fn e, acc ->
        Map.update(acc, e.currency, e.amount, &(&1 + e.amount))
      end)

    case Enum.find(balances, fn {_currency, total} -> total != 0 end) do
      nil -> :ok
      {currency, total} -> {:error, {:unbalanced, currency, total}}
    end
  end

  @doc """
  Validates the transaction and returns `{:ok, tx}` or
  `{:error, {:unbalanced, currency, total}}`.
  """
  def check(%__MODULE__{} = tx) do
    case validate(tx) do
      :ok -> {:ok, tx}
      error -> error
    end
  end
end
