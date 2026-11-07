# 03_audit.R
# Data audit: structure, missingness, structural blanks, duplicates,
# time formats, and value ranges.

library(arrow)
library(dplyr)

flights <- open_dataset("data/processed/flights")

# 1. Structure: column names and types
print(flights$schema)

# 2. Missing values (NA) per column
na_counts <- flights |>
  summarise(across(everything(), ~ sum(is.na(.x)))) |>
  collect() |>
  tidyr::pivot_longer(everything(), names_to = "column", values_to = "n_missing") |>
  mutate(pct = round(100 * n_missing / 7001619, 2)) |>
  arrange(desc(n_missing))
print(na_counts, n = 50)

# 3. Empty strings in text columns (fread keeps "" instead of NA)
flights |>
  summarise(
    empty_tail   = sum(Tail_Number == "", na.rm = TRUE),
    empty_cancel = sum(CancellationCode == "", na.rm = TRUE),
    empty_deptime = sum(DepTime == "", na.rm = TRUE),
    empty_arrtime = sum(ArrTime == "", na.rm = TRUE)
  ) |>
  collect() |> print()

# 4. Structural blanks: are missing values explained by flight status?
flights |>
  mutate(status = case_when(Cancelled == 1 ~ "cancelled",
                            Diverted  == 1 ~ "diverted",
                            TRUE           ~ "completed")) |>
  group_by(status) |>
  summarise(n = n(),
            na_DepDelay = sum(is.na(DepDelay)),
            na_ArrDelay = sum(is.na(ArrDelay)),
            na_AirTime  = sum(is.na(AirTime)),
            na_TaxiIn   = sum(is.na(TaxiIn))) |>
  collect() |> print()

# 5. Delay-cause columns should only be filled when ArrDel15 == 1
flights |>
  group_by(ArrDel15) |>
  summarise(n = n(),
            has_cause = sum(!is.na(CarrierDelay))) |>
  collect() |> print()

# 6. Cancellation codes (A = carrier, B = weather, C = NAS, D = security)
flights |> count(Cancelled, CancellationCode) |> collect() |> print()

# 7. Duplicates: same flight, same day, same route
dups <- flights |>
  count(FlightDate, Reporting_Airline, Flight_Number_Reporting_Airline,
        Origin, Dest) |>
  filter(n > 1) |>
  collect()
cat("Duplicate flight keys:", nrow(dups), "\n")

# 8. Time format: hhmm text; check lengths and "2400" (midnight)
flights |> count(len = nchar(CRSDepTime)) |> collect() |> print()
flights |>
  summarise(dep_2400 = sum(DepTime == "2400", na.rm = TRUE),
            arr_2400 = sum(ArrTime == "2400", na.rm = TRUE)) |>
  collect() |> print()

# 9. Value ranges for key numeric measures
flights |>
  summarise(
    min_DepDelay = min(DepDelay, na.rm = TRUE), max_DepDelay = max(DepDelay, na.rm = TRUE),
    min_ArrDelay = min(ArrDelay, na.rm = TRUE), max_ArrDelay = max(ArrDelay, na.rm = TRUE),
    min_TaxiOut  = min(TaxiOut,  na.rm = TRUE), max_TaxiOut  = max(TaxiOut,  na.rm = TRUE),
    min_AirTime  = min(AirTime,  na.rm = TRUE), max_AirTime  = max(AirTime,  na.rm = TRUE),
    min_Distance = min(Distance, na.rm = TRUE), max_Distance = max(Distance, na.rm = TRUE)
  ) |>
  collect() |> print()

# 10. Coverage: carriers and airports (watch for tiny groups)
flights |> count(Reporting_Airline, sort = TRUE) |> collect() |> print()
cat("Origin airports:", flights |> distinct(Origin) |> collect() |> nrow(), "\n")


# ---- Anomaly follow-ups ----

# A. The 1 completed flight with no arrival data
print(flights |> filter(Cancelled == 0, Diverted == 0, is.na(ArrDelay)) |> collect())

# B. The 2 flights with no scheduled elapsed time
print(flights |> filter(is.na(CRSElapsedTime)) |> collect())

# C. Empty tail numbers: by status, carrier, month
print(flights |> filter(Tail_Number == "") |> count(Cancelled, Diverted) |> collect())
print(flights |> filter(Tail_Number == "") |> count(Reporting_Airline, sort = TRUE) |> collect())
print(flights |> filter(Tail_Number == "") |> count(Month) |> collect())

# D. Cancelled flights that had already departed
print(flights |> filter(Cancelled == 1, !is.na(DepDelay)) |> count(CancellationCode) |> collect())

# E. Extreme taxi-out times (over 5 hours)
print(flights |> filter(TaxiOut > 300) |>
        select(FlightDate, Reporting_Airline, Origin, Dest, DepDelay, TaxiOut, Cancelled, Diverted) |>
        head(30) |> collect())
cat("TaxiOut > 300 min:", flights |> filter(TaxiOut > 300) |> collect() |> nrow(), "\n")

# F. Implausible speeds (mph from Distance and AirTime)
speed <- flights |> filter(!is.na(AirTime)) |>
  mutate(mph = Distance / (AirTime / 60)) |>
  filter(mph > 650 | mph < 100) |>
  select(FlightDate, Reporting_Airline, Origin, Dest, Distance, AirTime, mph)
print(speed |> head(30) |> collect())
cat("Implausible speed flights:", speed |> collect() |> nrow(), "\n")

# G. Extreme delays
print(flights |> summarise(over_6h  = sum(ArrDelay > 360,  na.rm = TRUE),
                           over_12h = sum(ArrDelay > 720,  na.rm = TRUE),
                           over_24h = sum(ArrDelay > 1440, na.rm = TRUE)) |> collect())

# H. ArrTime blanks by status
print(flights |> mutate(arr_blank = ArrTime == "") |>
        count(Cancelled, Diverted, arr_blank) |> collect())

# I. DepTime blanks vs DepDelay NA (the 421 mismatch)
print(flights |> mutate(dep_blank = DepTime == "", delay_na = is.na(DepDelay)) |>
        count(Cancelled, dep_blank, delay_na) |> collect())
print(flights |> filter(DepTime != "", is.na(DepDelay)) |>
        select(FlightDate, Reporting_Airline, Origin, Dest, CRSDepTime, DepTime,
               DepDelay, TaxiOut, Cancelled, CancellationCode) |>
        head(20) |> collect())



# 1. Fast-speed flights: clustered on certain dates? (daylight saving check)
print(speed |> filter(mph > 650) |> count(FlightDate, sort = TRUE) |> head(10) |> collect())
print(speed |> filter(mph > 650) |> collect() |> nrow())

# 2. Extreme delays (12h+): concentrated on certain days or carriers?
print(flights |> filter(ArrDelay > 720) |> count(FlightDate, sort = TRUE) |> head(10) |> collect())
print(flights |> filter(ArrDelay > 720) |> count(Reporting_Airline, sort = TRUE) |> collect())

# 3. The 421 mismatch: which carriers?
print(flights |> filter(DepTime != "", is.na(DepDelay)) |> count(Reporting_Airline, sort = TRUE) |> collect())