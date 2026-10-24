# 04_clean.R
# Applies audit decisions: recodes empty strings to NA, adds readable labels
# and derived variables, and flags anomalies (flags only, nothing deleted).
# Output: data/processed/flights_clean/ (parquet, partitioned by month)

library(arrow)
library(dplyr)

flights <- open_dataset("data/processed/flights")

clean <- flights |>
  mutate(
    # 1. Empty strings -> NA (audit: "" used instead of NA in text fields)
    Tail_Number      = if_else(Tail_Number == "", NA_character_, Tail_Number),
    CancellationCode = if_else(CancellationCode == "", NA_character_, CancellationCode),
    DepTime          = if_else(DepTime == "", NA_character_, DepTime),
    ArrTime          = if_else(ArrTime == "", NA_character_, ArrTime),
    
    # 2. Flight status (explains structural blanks)
    status = case_when(Cancelled == 1 ~ "Cancelled",
                       Diverted  == 1 ~ "Diverted",
                       TRUE           ~ "Completed"),
    
    # 3. Readable cancellation reason
    cancel_reason = case_when(CancellationCode == "A" ~ "Carrier",
                              CancellationCode == "B" ~ "Weather",
                              CancellationCode == "C" ~ "NAS",
                              CancellationCode == "D" ~ "Security"),
    
    # 4. Scheduled hour of day (from schedule, exists for every flight; 24 -> 0)
    dep_hour = as.integer(substr(CRSDepTime, 1, 2)),
    dep_hour = if_else(dep_hour == 24L, 0L, dep_hour),
    arr_hour = as.integer(substr(CRSArrTime, 1, 2)),
    arr_hour = if_else(arr_hour == 24L, 0L, arr_hour),
    
    # 5. Carrier names and regional flag
    carrier_name = case_when(
      Reporting_Airline == "WN" ~ "Southwest",  Reporting_Airline == "DL" ~ "Delta",
      Reporting_Airline == "AA" ~ "American",   Reporting_Airline == "OO" ~ "SkyWest",
      Reporting_Airline == "UA" ~ "United",     Reporting_Airline == "YX" ~ "Republic",
      Reporting_Airline == "MQ" ~ "Envoy",      Reporting_Airline == "OH" ~ "PSA",
      Reporting_Airline == "AS" ~ "Alaska",     Reporting_Airline == "B6" ~ "JetBlue",
      Reporting_Airline == "F9" ~ "Frontier",   Reporting_Airline == "NK" ~ "Spirit",
      Reporting_Airline == "G4" ~ "Allegiant",  Reporting_Airline == "HA" ~ "Hawaiian"),
    is_regional = Reporting_Airline %in% c("OO", "YX", "MQ", "OH"),
    
    # 6. Route
    route = paste0(Origin, "-", Dest),
    
    # 7. Anomaly flags (investigated, NOT deleted)
    flag_long_taxiout    = coalesce(TaxiOut > 300, FALSE),                       # > 5 h taxi
    flag_fast_speed      = coalesce(Distance / (AirTime / 60) > 650, FALSE),     # likely recording error
    flag_slow_speed      = coalesce(Distance / (AirTime / 60) < 100, FALSE),     # likely holding/vectoring
    flag_extreme_delay   = coalesce(ArrDelay > 720, FALSE),                      # > 12 h late
    flag_missing_arrival = status == "Completed" & is.na(ArrDelay)               # 1 flight
    ) 

write_dataset(clean, "data/processed/flights_clean", partitioning = "Month")
message("Clean dataset written.")