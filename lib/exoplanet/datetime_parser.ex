# Generated from lib/exoplanet/datetime_parser.ex.exs, do not edit.
# Generated at 2025-03-28 03:28:25Z.

defmodule Exoplanet.DateTimeParser do
  @moduledoc false
  def parse(dt) when is_binary(dt) do
    with {:ok, tokens, _, _, _, _} <- datetime(dt),
         [day, month, year, hour, minute, second, _zone_abbr] <- normalize_seconds(tokens),
         {:ok, dt} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      dt
    end
  end

  defp normalize_seconds([_day, _month, _year, _hour, _minute, _second, _zone_abbr] = terms),
    do: terms

  defp normalize_seconds([day, month, year, hour, minute, zone_abbr]),
    do: [day, month, year, hour, minute, 0, zone_abbr]

  def normalize_year(offset) when offset < 2000, do: 2000 + offset
  def normalize_year(year), do: year

  @doc """
  Parses the given `binary` as datetime.

  Returns `{:ok, [token], rest, context, position, byte_offset}` or
  `{:error, reason, rest, context, line, byte_offset}` where `position`
  describes the location of the datetime (start position) as `{line, offset_to_start_of_line}`.

  To column where the error occurred can be inferred from `byte_offset - offset_to_start_of_line`.

  ## Options

    * `:byte_offset` - the byte offset for the whole binary, defaults to 0
    * `:line` - the line and the byte offset into that line, defaults to `{1, byte_offset}`
    * `:context` - the initial context value. It will be converted to a map

  """
  @spec datetime(binary, keyword) ::
          {:ok, [term], rest, context, line, byte_offset}
          | {:error, reason, rest, context, line, byte_offset}
        when line: {pos_integer, byte_offset},
             byte_offset: non_neg_integer,
             rest: binary,
             reason: String.t(),
             context: map
  def datetime(binary, opts \\ []) when is_binary(binary) do
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

  defp datetime__5(rest, acc, stack, context, line, offset) do
    datetime__6(rest, [], [acc | stack], context, line, offset)
  end

  defp datetime__6(
         <<x0, x1, x2, x3, rest::binary>>,
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
      [x3 - 48 + (x2 - 48) * 10 + (x1 - 48) * 100 + (x0 - 48) * 1000] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 4
    )
  end

  defp datetime__6(<<x0, x1, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) do
    datetime__7(
      rest,
      [x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 2
    )
  end

  defp datetime__6(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\" or ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\"",
     rest, context, line, offset}
  end

  defp datetime__7(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    datetime__8(
      rest,
      Enum.map(user_acc, fn var -> Exoplanet.DateTimeParser.normalize_year(var) end) ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp datetime__8(
         <<" ", x0, x1, ":", x2, x3, rest::binary>>,
         acc,
         stack,
         context,
         comb__line,
         comb__offset
       )
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) and (x2 >= 48 and x2 <= 57) and
              (x3 >= 48 and x3 <= 57) do
    datetime__9(
      rest,
      [x3 - 48 + (x2 - 48) * 10, x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 6
    )
  end

  defp datetime__8(rest, _acc, _stack, context, line, offset) do
    {:error,
     "expected string \" \", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\", followed by string \":\", followed by ASCII character in the range \"0\" to \"9\", followed by ASCII character in the range \"0\" to \"9\"",
     rest, context, line, offset}
  end

  defp datetime__9(<<":", x0, x1, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 48 and x0 <= 57 and (x1 >= 48 and x1 <= 57) do
    datetime__10(
      rest,
      [x1 - 48 + (x0 - 48) * 10] ++ acc,
      stack,
      context,
      comb__line,
      comb__offset + 3
    )
  end

  defp datetime__9(<<rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__10(rest, [] ++ acc, stack, context, comb__line, comb__offset)
  end

  defp datetime__10(<<" ", rest::binary>>, acc, stack, context, comb__line, comb__offset) do
    datetime__11(rest, [] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp datetime__10(rest, _acc, _stack, context, line, offset) do
    {:error, "expected string \" \"", rest, context, line, offset}
  end

  defp datetime__11(rest, acc, stack, context, line, offset) do
    datetime__12(rest, [], [acc | stack], context, line, offset)
  end

  defp datetime__12(rest, acc, stack, context, line, offset) do
    datetime__14(rest, acc, [3 | stack], context, line, offset)
  end

  defp datetime__14(<<x0, rest::binary>>, acc, stack, context, comb__line, comb__offset)
       when x0 >= 65 and x0 <= 90 do
    datetime__15(rest, [x0] ++ acc, stack, context, comb__line, comb__offset + 1)
  end

  defp datetime__14(rest, acc, stack, context, line, offset) do
    datetime__13(rest, acc, stack, context, line, offset)
  end

  defp datetime__13(rest, acc, [_ | stack], context, line, offset) do
    datetime__16(rest, acc, stack, context, line, offset)
  end

  defp datetime__15(rest, acc, [1 | stack], context, line, offset) do
    datetime__16(rest, acc, stack, context, line, offset)
  end

  defp datetime__15(rest, acc, [count | stack], context, line, offset) do
    datetime__14(rest, acc, [count - 1 | stack], context, line, offset)
  end

  defp datetime__16(rest, user_acc, [acc | stack], context, line, offset) do
    _ = user_acc

    datetime__17(
      rest,
      [List.to_string(:lists.reverse(user_acc))] ++ acc,
      stack,
      context,
      line,
      offset
    )
  end

  defp datetime__17(rest, acc, _stack, context, line, offset) do
    {:ok, acc, rest, context, line, offset}
  end
end
