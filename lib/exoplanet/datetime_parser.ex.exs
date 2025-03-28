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
  # or four characters (four preferred).
  year = choice([integer(4), integer(2)])

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

  def parse(dt) when is_binary(dt) do
    with {:ok, tokens, _, _, _, _} <- datetime(dt),
         [day, month, year, hour, minute, second] <- normalize_seconds(tokens),
         year <- normalize_year(year),
         {:ok, dt} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      dt
    end
  end

  defp normalize_seconds([_day, _month, _year, _hour, _minute, _second] = terms),
    do: terms

  defp normalize_seconds([day, month, year, hour, minute]),
    do: [day, month, year, hour, minute, 0]

  defp normalize_year(offset) when offset < 2000, do: 2000 + offset
  defp normalize_year(year), do: year
end
