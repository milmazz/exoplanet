# Generated from lib/exoplanet/datetime_parser.ex.exs, do not edit.
# Generated at 2025-03-28 12:14:22Z.

defmodule Exoplanet.DateTimeParser do
  @moduledoc false
  @spec datetime(binary, keyword) ::
          {:ok, [term], rest, context, line, byte_offset}
          | {:error, reason, rest, context, line, byte_offset}
        when line: {pos_integer, byte_offset},
             byte_offset: non_neg_integer,
             rest: binary,
             reason: String.t(),
             context: map
  defp datetime(binary, opts \\ []) when is_binary(binary) do
    context = Map.new(Keyword.get(opts, :context, []))
    byte_offset = Keyword.get(opts, :byte_offset, 0)

    line =
      case Keyword.get(opts, :line, 1) do
        {_, _} = line -> line
        line -> {line, byte_offset}
      end

    case datetime__0(binary, [], [], context, line, byte_offset) do
      {:ok, acc, rest, context, line, offset} ->
        {:ok, :lists.reverse(acc), rest, context, line, offset}

      {:error, _, _, _, _, _} = error ->
        error
    end
  end

  defp datetime__0(
         <<x0, x1, x2, ", ", rest::binary>>,
         acc,
         stack,
         context,
         comb__line,
         comb__offset
       )
       when x0 >= 65 and x0 <= 122 and (x1 >= 65 and x1 <= 122) and (x2 >= 65 and x2 <= 122) do
    datetime__1(rest, [] ++ acc, stack, context, comb__line, comb__offset + 5)
  end

  defp datetime__0(<<rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__1(rest, [] ++ acc, stack, context, comb__line, comb__offset)
  end

  defp datetime__1(<<x0, x1, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) do
    datetime__2(
      rest,
      [x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 2
    )
  end

  defp datetime__1(<<x0, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 do
    datetime__2(rest, [x0 - 48] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp datetime__1(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\" or ASCII character in the range \"0\" to \"9\"",
     rest, context, line, offset}
  end

  defp datetime__2(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__3(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp datetime__2(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp datetime__3(<<"Jan", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, [1] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Feb", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, [2] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Mar", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, [3] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Apr", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, [4] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"May", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, [5] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Jun", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, [6] ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Jul", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, ~c"\a" ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Aug", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, ~c"\b" ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Sep", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, ~c"\t" ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Oct", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, ~c"\n" ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Nov", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, ~c"\v" ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(<<"Dec", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__4(rest, ~c"\f" ++ acc, stack, context, comb__line, comb__offset + 3)
  end

  defp datetime__3(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \"Jan\" or string \"Feb\" or string \"Mar\" or string \"Apr\" or string \"May\" or string \"Jun\" or string \"Jul\" or string \"Aug\" or string \"Sep\" or string \"Oct\" or string \"Nov\" or string \"Dec\"",
     rest, context, line, offset}
  end

  defp datetime__4(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__5(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp datetime__4(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp datetime__5(
         <<x0, x1, x2, x3, rest::binary>>,
         acc,
         stack,
         context,
         comb__line,
         comb__offset
       )
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) and (x2 >= 48 and x2 <= 57) and
              (x3 >= 48 and x3 <= 57) do
    datetime__6(
      rest,
      [x3 - 48 + (x2 - 48) * 10 + (x1 - 48) * 100 + (x0 - 48) * 1000] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 4
    )
  end

  defp datetime__5(<<x0, x1, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) do
    datetime__6(
      rest,
      [x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 2
    )
  end

  defp datetime__5(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\" or ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\"",
     rest, context, line, offset}
  end

  defp datetime__6(
         <<" ", x0, x1, ":", x2, x3, rest::binary>>,
         acc,
         stack,
         context,
         comb__line,
         comb__offset
       )
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) and (x2 >= 48 and x2 <= 57) and
              (x3 >= 48 and x3 <= 57) do
    datetime__7(
      rest,
      [x3 - 48 + (x2 - 48) * 10, x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 6
    )
  end

  defp datetime__6(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \" \", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\", followed by string \":\", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\"",
     rest, context, line, offset}
  end

  defp datetime__7(<<":", x0, x1, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) do
    datetime__8(
      rest,
      [x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 3
    )
  end

  defp datetime__7(<<rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__8(rest, [] ++ acc, stack, context, comb__line, comb__offset)
  end

  defp datetime__8(rest, acc, _stack, context, line, offset) do
    {:ok, acc, rest, context, line, offset}
  end

  alias Exoplanet.ParseError

  def parse(dt) when is_binary(dt) do
    with {:ok, tokens, _, _, _, _} <- datetime(dt) do
      [day, month, year, hour, minute, second] = normalize_seconds(tokens)
      year = normalize_year(year)
      NaiveDateTime.new(year, month, day, hour, minute, second)
    end
  end

  def parse!(dt) do
    case parse(dt) do
      {:ok, dt} ->
        dt

      {:error, reason} ->
        raise ParseError, message: "#{inspect(reason)}"

      {:error, reason, _rest, _context, _line, _byte_offset} ->
        raise ParseError, message: reason
    end
  end

  defp normalize_seconds([_day, _month, _year, _hour, _minute, _second] = terms),
    do: terms

  defp normalize_seconds([day, month, year, hour, minute]),
    do: [day, month, year, hour, minute, 0]

  defp normalize_year(offset) when offset < 2000, do: 2000 + offset
  defp normalize_year(year), do: year
end
