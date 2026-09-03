defmodule ZerobookTest do
  use ExUnit.Case, async: true
  doctest Zerobook

  alias Zerobook.Transaction

  describe "Zerobook facade" do
    test "exposes entry/transaction constructors" do
      assert Zerobook.entry("a", 1, "BRL").account == "a"

      tx =
        Zerobook.transaction("t1", [
          Zerobook.entry("1000.cash", 5, "BRL"),
          Zerobook.entry("2000.revenue", -5, "BRL")
        ])

      assert Transaction.validate(tx) == :ok
    end

    test "exposes ledger helpers" do
      t1 =
        Zerobook.transaction("t1", [
          Zerobook.entry("1000.cash", 5, "BRL"),
          Zerobook.entry("2000.revenue", -5, "BRL")
        ])

      t2 =
        Zerobook.transaction("t2", [
          Zerobook.entry("1000.cash", 7, "BRL"),
          Zerobook.entry("2000.revenue", -7, "BRL")
        ])

      assert {:ok, l1} = Zerobook.append(Zerobook.new_ledger(), t1)
      assert {:ok, ledger} = Zerobook.append(l1, t2)

      assert Zerobook.verify(ledger) == :ok
      assert Zerobook.balance_of(ledger, "1000.cash", "BRL") == 12
    end
  end
end
