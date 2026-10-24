# 02_combine.R
# Unzips each monthly file, keeps the selected fields, and writes
# one parquet file per month to data/processed/flights/.

library(data.table)
library(arrow)

raw_dir <- "data/raw"
out_dir <- "data/processed/flights"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

keep <- c(
  # time
  "Year", "Month", "DayofMonth", "DayOfWeek", "FlightDate",
  # carrier & flight
  "Reporting_Airline", "Flight_Number_Reporting_Airline", "Tail_Number",
  # origin / destination
  "OriginAirportID", "Origin", "OriginCityName", "OriginState", "OriginCityMarketID",
  "DestAirportID", "Dest", "DestCityName", "DestState", "DestCityMarketID", "Distance",
  # performance
  "CRSDepTime", "DepTime", "DepDelay", "DepDel15", "TaxiOut", "TaxiIn",
  "CRSArrTime", "ArrTime", "ArrDelay", "ArrDel15",
  "CRSElapsedTime", "ActualElapsedTime", "AirTime",
  # irregular operations
  "Cancelled", "CancellationCode", "Diverted",
  "CarrierDelay", "WeatherDelay", "NASDelay", "SecurityDelay", "LateAircraftDelay"
)

time_cols <- c("CRSDepTime", "DepTime", "CRSArrTime", "ArrTime")  # keep hhmm as text

zips <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE)

for (z in zips) {
  csv <- grep("\\.csv$", unzip(z, list = TRUE)$Name, value = TRUE)
  unzip(z, files = csv, exdir = tempdir())          # extract to a temp folder
  csv_path <- file.path(tempdir(), csv)
  
  dt <- fread(csv_path, select = keep,
              colClasses = list(character = time_cols))
  
  month <- dt$Month[1]
  write_parquet(dt, file.path(out_dir, sprintf("month_%02d.parquet", month)))
  message("Month ", month, ": ", nrow(dt), " rows")
  
  file.remove(csv_path)                             # delete the temp CSV to save disk
}
