defmodule Exoplanet.DateTimeParserTest do
  use ExUnit.Case, async: true
  alias Exoplanet.DateTimeParser

  describe "parse!/1" do
    test "parses a string that follows the RFC 2822" do
      assert ~N[2025-03-07 11:00:00] == DateTimeParser.parse!("Fri, 07 Mar 25 11:00:00 EST")
      assert ~N[2024-11-18 11:00:00] == DateTimeParser.parse!("Mon, 18 Nov 2024 11:00:00 EST")
      assert ~N[2024-11-18 11:00:00] == DateTimeParser.parse!("Mon, 18 Nov 2024 11:00 EST")
      assert ~N[2024-11-18 11:00:00] == DateTimeParser.parse!("18 Nov 2024 11:00 EST")
      assert ~N[2025-01-16 16:17:09] == DateTimeParser.parse!("Thu, 16 Jan 2025 16:17:09 +0000")
    end

    test "four-digit years pass through unchanged, including pre-2000" do
      assert ~N[1999-11-18 11:00:00] == DateTimeParser.parse!("Thu, 18 Nov 1999 11:00:00 EST")
      assert ~N[1970-01-01 00:00:00] == DateTimeParser.parse!("Thu, 01 Jan 1970 00:00:00 GMT")
    end

    test "two-digit years follow the RFC 2822 century rule" do
      # 00-49 → 2000s
      assert ~N[2049-11-18 11:00:00] == DateTimeParser.parse!("Thu, 18 Nov 49 11:00:00 EST")
      assert ~N[2000-11-18 11:00:00] == DateTimeParser.parse!("Sat, 18 Nov 00 11:00:00 EST")
      # 50-99 → 1900s
      assert ~N[1950-11-18 11:00:00] == DateTimeParser.parse!("Sat, 18 Nov 50 11:00:00 EST")
      assert ~N[1999-11-18 11:00:00] == DateTimeParser.parse!("Thu, 18 Nov 99 11:00:00 EST")
    end

    test "raises with invalid input" do
      assert_raise Exoplanet.ParseError, ~r/^expected ASCII character in the range/, fn ->
        DateTimeParser.parse!("foo")
      end

      assert_raise Exoplanet.ParseError, ~r/^:invalid_date/, fn ->
        DateTimeParser.parse!("32 Nov 2024 11:00 EST")
      end
    end
  end

  describe "parse/1" do
    test "returns {:ok, t} on success and a two-element {:error, reason} on failure" do
      assert {:ok, ~N[2024-11-18 11:00:00]} =
               DateTimeParser.parse("Mon, 18 Nov 2024 11:00:00 EST")

      # Parsec failure: reason is the parser's message string.
      assert {:error, reason} = DateTimeParser.parse("foo")
      assert is_binary(reason)

      # Calendar failure: reason comes from NaiveDateTime.new/6.
      assert {:error, :invalid_date} = DateTimeParser.parse("32 Nov 2024 11:00 EST")
    end
  end
end
