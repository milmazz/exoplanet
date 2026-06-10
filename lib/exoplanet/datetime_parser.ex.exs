defmodule Exoplanet.DateTimeParser do
  @moduledoc false
  # parsec:Exoplanet.DateTimeParser
  import NimbleParsec

  # Reference: https://www.w3.org/Protocols/rfc822/#z28

  space = string(" ")

  month =
    choice([
      "Jan" |> string() |> replace(1),
      "Feb" |> string() |> replace(2),
      "Mar" |> string() |> replace(3),
      "Apr" |> string() |> replace(4),
      "May" |> string() |> replace(5),
      "Jun" |> string() |> replace(6),
      "Jul" |> string() |> replace(7),
      "Aug" |> string() |> replace(8),
      "Sep" |> string() |> replace(9),
      "Oct" |> string() |> replace(10),
      "Nov" |> string() |> replace(11),
      "Dec" |> string() |> replace(12)
    ])

  day_of_week = ascii_string([?A..?z], 3)

  # All date-times in RSS conform to the Date and Time Specification of RFC 822,
  # with the exception that the year may be expressed with two characters
  # or four characters (four preferred). Four-digit years pass through
  # unchanged; two-digit years follow the RFC 2822 §4.3 obsolete-date rule
  # (00-49 → 2000s, 50-99 → 1900s), resolved at parse time so the rest of
  # the pipeline only ever sees a full year.
  year =
    choice([
      integer(4),
      integer(2) |> map(:normalize_two_digit_year)
    ])

  # date        =  1*2DIGIT month 2DIGIT        ; day month year
  #                                             ;  e.g. 20 Jun 82
  date =
    choice([integer(2), integer(1)])
    |> ignore(space)
    |> concat(month)
    |> ignore(space)
    |> concat(year)

  # hour        =  2DIGIT ":" 2DIGIT [":" 2DIGIT]
  #                                             ; 00:00:00 - 23:59:59
  hour =
    integer(2)
    |> ignore(string(":"))
    |> integer(2)
    |> optional(string(":") |> ignore() |> integer(2))

  # time        =  hour zone                    ; ANSI and Military
  # NOTE: I will ignore the zone, given the result will be a `NaiveDateTime`
  # time =
  #   hour
  #   |> ignore(space)
  #   |> concat(zone)

  # date-time   =  [ day "," ] date time        ; dd mm yy
  #                                             ;  hh:mm:ss zzz
  date_time =
    day_of_week
    |> ignore()
    |> ignore(string(", "))
    |> optional()
    |> concat(date)
    |> ignore(space)
    |> concat(hour)

  defparsecp(:datetime, date_time)
  # parsec:Exoplanet.DateTimeParser

  alias Exoplanet.ParseError

  @spec parse(binary()) :: {:ok, NaiveDateTime.t()} | {:error, String.t() | atom()}
  def parse(dt) when is_binary(dt) do
    case datetime(dt) do
      {:ok, tokens, _rest, _context, _line, _byte_offset} ->
        [day, month, year, hour, minute, second] = normalize_seconds(tokens)
        NaiveDateTime.new(year, month, day, hour, minute, second)

      {:error, reason, _rest, _context, _line, _byte_offset} ->
        {:error, reason}
    end
  end

  @spec parse!(binary()) :: NaiveDateTime.t()
  def parse!(dt) do
    case parse(dt) do
      {:ok, dt} ->
        dt

      {:error, reason} when is_binary(reason) ->
        raise ParseError, message: reason

      {:error, reason} ->
        raise ParseError, message: "#{inspect(reason)}"
    end
  end

  defp normalize_seconds([_day, _month, _year, _hour, _minute, _second] = terms),
    do: terms

  defp normalize_seconds([day, month, year, hour, minute]),
    do: [day, month, year, hour, minute, 0]

  # RFC 2822 §4.3: two-digit years 00-49 belong to the 2000s, 50-99 to the
  # 1900s. Called at parse time via `map/2` in the `year` combinator above.
  defp normalize_two_digit_year(offset) when offset < 50, do: 2000 + offset
  defp normalize_two_digit_year(offset), do: 1900 + offset
end
