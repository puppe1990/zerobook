defmodule Zerobook.Entry do
  @moduledoc """
  A single line of a double-entry `Zerobook.Transaction`.

  An entry moves `amount` units (integers only — use cents, attos, etc.)
  in `currency` to or from the ledger account named `account`.

  * positive `amount` debits the account (money flows in)
  * negative `amount` credits the account (money flows out)

  The sign convention is arbitrary but must be consistent across the
  ledger; what matters for correctness is that every transaction sums to
  zero per currency.
  """

  @type t :: %__MODULE__{
          account: String.t(),
          amount: integer(),
          currency: String.t(),
          description: String.t() | nil
        }

  defstruct [:account, :amount, :currency, :description]

  @doc """
  Builds an entry.

  ## Examples

      iex> Zerobook.Entry.new("1000.cash", 1_000, "BRL", "opening")
      %Zerobook.Entry{account: "1000.cash", amount: 1000, currency: "BRL", description: "opening"}

  """
  def new(account, amount, currency, description \\ nil) do
    %__MODULE__{
      account: account,
      amount: amount,
      currency: currency,
      description: description
    }
  end

  @doc false
  def canonical(%__MODULE__{} = entry) do
    "#{entry.account}|#{entry.amount}|#{entry.currency}|#{entry.description || ""}"
  end
end
