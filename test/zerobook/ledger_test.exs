defmodule Zerobook.LedgerTest do
  use ExUnit.Case, async: true

  alias Zerobook.{Entry, Ledger, Transaction}

  defp cash_tx(id, amount, currency \\ "BRL", opts \\ []) do
    Transaction.new(id, [
      Entry.new("1000.cash", amount, currency, Keyword.get(opts, :note)),
      Entry.new("2000.revenue", -amount, currency)
    ])
  end

  describe "append/2" do
    test "appends balanced transactions and chains hashes" do
      assert {:ok, l1} = Ledger.append(Ledger.new(), cash_tx("t1", 100))
      assert {:ok, l2} = Ledger.append(l1, cash_tx("t2", 50))

      assert [b1, b2] = Ledger.blocks(l2)
      assert b1.index == 0 and b2.index == 1
      assert b1.prev_hash == <<0::256>>
      assert b2.prev_hash == b1.hash
      assert b1.hash != b2.hash
      assert Ledger.verify(l2) == :ok
    end

    test "rejects unbalanced transactions" do
      bad = Transaction.new("bad", [Entry.new("1000.cash", 100, "BRL")])

      assert {:error, {:unbalanced, "BRL", 100}} = Ledger.append(Ledger.new(), bad)
    end

    test "rejects duplicate transaction ids" do
      assert {:ok, l1} = Ledger.append(Ledger.new(), cash_tx("t1", 100))

      assert {:error, {:duplicate_transaction, "t1"}} = Ledger.append(l1, cash_tx("t1", 10))
    end

    test "supports multiple currencies per transaction" do
      multi =
        Transaction.new("multi", [
          Entry.new("1000.cash", 100, "BRL"),
          Entry.new("2000.revenue", -100, "BRL"),
          Entry.new("1000.cash", 5, "USD"),
          Entry.new("2000.revenue", -5, "USD")
        ])

      assert {:ok, ledger} = Ledger.append(Ledger.new(), multi)
      assert Ledger.balance_of(ledger, "1000.cash", "BRL") == 100
      assert Ledger.balance_of(ledger, "1000.cash", "USD") == 5
    end

    test "negative amounts credit an account" do
      tx =
        Transaction.new("t", [
          Entry.new("3000.expense", 25, "BRL"),
          Entry.new("1000.cash", -25, "BRL")
        ])

      assert {:ok, ledger} = Ledger.append(Ledger.new(), tx)
      assert Ledger.balance_of(ledger, "1000.cash", "BRL") == -25
      assert Ledger.balance_of(ledger, "3000.expense", "BRL") == 25
    end
  end

  describe "verify/1 tamper detection" do
    test "detects amount tampering in a past block" do
      ledger =
        Ledger.new()
        |> Ledger.append!(cash_tx("t1", 100))
        |> Ledger.append!(cash_tx("t2", 50))

      [tampered | _] =
        Ledger.blocks(ledger)
        |> Enum.map(& &1.transaction)
        |> Enum.map(fn
          %Transaction{id: "t1"} = tx ->
            [%Entry{} = e | rest] = tx.entries
            %{tx | entries: [%{e | amount: 9_999} | rest]}

          tx ->
            tx
        end)

      # rewrite first block in-place with new entries but stale hash
      [b1, b2] = Ledger.blocks(ledger)
      forged = %{b1 | transaction: tampered}

      broken = %{ledger | blocks: [forged, b2]}

      assert {:error, {:bad_hash, 0}} = Ledger.verify(broken)
    end

    test "detects hash-chain breaks when a block is removed" do
      ledger =
        Ledger.new()
        |> Ledger.append!(cash_tx("t1", 100))
        |> Ledger.append!(cash_tx("t2", 50))

      # simulate deletion of the first block: block 1 (index 1) now leads the
      # chain but still points at block 0's hash, which is not the genesis hash
      [b2] = Ledger.blocks(ledger) |> Enum.drop(1)
      broken = %{ledger | blocks: [b2]}

      assert {:error, {:broken_link, 0}} = Ledger.verify(broken)
    end

    test "detects reordering of blocks" do
      ledger =
        Ledger.new()
        |> Ledger.append!(cash_tx("t1", 100))
        |> Ledger.append!(cash_tx("t2", 50))

      [b1, b2] = Ledger.blocks(ledger)
      swapped = %{ledger | blocks: [b2, b1]}

      assert {:error, {:broken_link, 0}} = Ledger.verify(swapped)
    end

    test "detects edits to entry description" do
      ledger = Ledger.new() |> Ledger.append!(cash_tx("t1", 100, "BRL", note: "original"))

      [%{transaction: tx} = b] = Ledger.blocks(ledger)

      forged = %{
        b
        | transaction: %{
            tx
            | entries: [%{hd(tx.entries) | description: "tampered"} | tl(tx.entries)]
          }
      }

      assert {:error, {:bad_hash, 0}} = Ledger.verify(%{ledger | blocks: [forged]})
    end
  end

  describe "queries" do
    test "balance_of accumulates across transactions" do
      ledger =
        Ledger.new()
        |> Ledger.append!(cash_tx("t1", 100))
        |> Ledger.append!(cash_tx("t2", 50))
        |> Ledger.append!(cash_tx("t3", -30))

      assert Ledger.balance_of(ledger, "1000.cash", "BRL") == 120
      assert Ledger.balance_of(ledger, "2000.revenue", "BRL") == -120
      assert Ledger.balance_of(ledger, "missing", "BRL") == 0
    end

    test "statements returns postings for an account" do
      ledger =
        Ledger.new()
        |> Ledger.append!(cash_tx("t1", 100))
        |> Ledger.append!(cash_tx("t2", 50))

      assert [{tx1, _}, {tx2, _}] = Ledger.statements(ledger, "1000.cash")
      assert tx1.id == "t1" and tx2.id == "t2"
      assert Ledger.statements(ledger, "nope") == []
    end

    test "last_block returns nil for empty ledger" do
      assert Ledger.last_block(Ledger.new()) == nil
    end

    test "verify passes on the doctest quick start" do
      ledger =
        Zerobook.new_ledger()
        |> Ledger.append!(
          Zerobook.transaction("txn_1", [
            Zerobook.entry("1000.cash", 10_000, "BRL", "deposit"),
            Zerobook.entry("2000.revenue", -10_000, "BRL")
          ])
        )
        |> Ledger.append!(
          Zerobook.transaction("txn_2", [
            Zerobook.entry("3000.expense", 2_500, "BRL", "hosting"),
            Zerobook.entry("1000.cash", -2_500, "BRL")
          ])
        )

      assert Zerobook.verify(ledger) == :ok
      assert Zerobook.balance_of(ledger, "1000.cash", "BRL") == 7_500
    end
  end
end
