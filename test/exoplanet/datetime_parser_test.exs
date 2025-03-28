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

    test "raises with invalid input" do
      assert_raise Exoplanet.ParseError, ~r/^expected ASCII character in the range/, fn ->
        DateTimeParser.parse!("foo")
      end

      assert_raise Exoplanet.ParseError, ~r/^:invalid_date/, fn ->
        DateTimeParser.parse!("32 Nov 2024 11:00 EST")
      end
    end
  end
end
