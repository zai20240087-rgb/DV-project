# 01_download.R
# Downloads the 12 monthly 2025 On-Time Performance files from BTS TranStats
# into data/raw/. Raw files are never edited.

options(timeout = 1200)  # files are large; default 60s timeout is too short

raw_dir <- "data/raw"
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

base_url <- "https://transtats.bts.gov/PREZIP/"

for (m in 1:12) {
  file <- sprintf("On_Time_Reporting_Carrier_On_Time_Performance_1987_present_2025_%d.zip", m)
  dest <- file.path(raw_dir, file)
  if (!file.exists(dest)) {            # skip months already downloaded
    message("Downloading month ", m)
    download.file(paste0(base_url, file), dest, mode = "wb")
  }
}

# Log what was downloaded (copy this into the README)
log <- data.frame(file = list.files(raw_dir, pattern = "\\.zip$"),
                  downloaded = Sys.Date())
print(log)
