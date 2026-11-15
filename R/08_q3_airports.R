# 08_q3_airports.R
# Q3: Where are delays concentrated, and do airport differences remain after
#     accounting for carrier, month and time of day?
# Input:  data/processed/flights_clean/ (from 04_clean.R)
#         data/raw/T_MASTER_CORD_*.zip (BTS Master Coordinate table)
# Output: figures/fig_q3a_map.png
#         figures/fig_q3b_adjusted.png
# Needs the 'maps' package for the US state outline: install.packages("maps")

library(arrow); library(dplyr); library(tidyr); library(ggplot2)
source("R/00_theme.R")

fc <- open_dataset("data/processed/flights_clean")
dir.create("figures", showWarnings = FALSE)

# ---- 1. Airport coordinates (latest record for each airport) ----
mc_zip <- list.files("data/raw", pattern = "^T_MASTER_CORD.*\\.zip$", full.names = TRUE)[1]
mc <- read.csv(unz(mc_zip, "T_MASTER_CORD.csv")) |>
  filter(AIRPORT_IS_LATEST == 1) |>
  select(AIRPORT_ID, AIRPORT, DISPLAY_AIRPORT_NAME, AIRPORT_STATE_CODE, LATITUDE, LONGITUDE)
cat("Master Coordinate airports (latest):", nrow(mc), "\n")

# ---- 2. Departures by airport x carrier x month x scheduled hour ----
cells_ap <- fc |>
  group_by(Origin, OriginAirportID, Reporting_Airline, Month, dep_hour) |>
  summarise(flights   = n(),
            cancelled = sum(Cancelled),
            known     = sum(!is.na(DepDel15)),
            late      = sum(DepDel15, na.rm = TRUE)) |>
  collect()

# Expected late rate for each carrier x month x hour, nationally
cells <- cells_ap |>
  group_by(Reporting_Airline, Month, dep_hour) |>
  summarise(exp = sum(late) / sum(known), .groups = "drop")
national <- sum(cells_ap$late) / sum(cells_ap$known)
cat("National departure late rate:", round(national, 4), "\n")

# ---- 3. Airport profile: raw vs expected vs adjusted ----
# expected = late rate the airport would have if each of its flights performed
#            like the national average for the same carrier, month and hour
# adjusted = (observed / expected) x national rate
airports <- cells_ap |>
  left_join(cells, by = c("Reporting_Airline", "Month", "dep_hour")) |>
  group_by(Origin, OriginAirportID) |>
  summarise(flights     = sum(flights),
            cancel_rate = sum(cancelled) / sum(flights),
            dep_late    = sum(late) / sum(known),
            exp_late    = sum(known * exp, na.rm = TRUE) / sum(known),
            .groups = "drop") |>
  mutate(oe = dep_late / exp_late, adj_late = oe * national) |>
  arrange(desc(flights))

cat("Airports:", nrow(airports), " with >= 10,000 departures:", sum(airports$flights >= 10000),
    " their share of flights:", round(sum(airports$flights[airports$flights >= 10000]) / sum(airports$flights), 3), "\n")
cat("Airports without coordinates:", sum(!airports$OriginAirportID %in% mc$AIRPORT_ID), "\n")

top30 <- airports |> slice_head(n = 30) |>
  mutate(raw_rank = rank(-dep_late), adj_rank = rank(-adj_late)) |>
  arrange(desc(adj_late))
print(top30 |> mutate(across(c(dep_late, exp_late, adj_late), ~ round(.x, 3)), oe = round(oe, 2)) |>
        select(Origin, flights, dep_late, exp_late, adj_late, oe, raw_rank, adj_rank), n = 30)

# ---- 4. Stability: monthly rank among the 30 busiest airports ----
monthly_rank <- cells_ap |>
  filter(Origin %in% top30$Origin) |>
  group_by(Origin, Month) |>
  summarise(rate = sum(late) / sum(known), .groups = "drop") |>
  group_by(Month) |> mutate(rank = rank(-rate)) |> ungroup()
print(monthly_rank |> group_by(Origin) |>
        summarise(top5_months = sum(rank <= 5), top10_months = sum(rank <= 10),
                  median_rank = median(rank)) |>
        arrange(median_rank), n = 30)

# ---- 5. Same carrier at different hubs (is DFW the airport or American?) ----
print(cells_ap |> filter(Reporting_Airline == "AA",
                         Origin %in% c("DFW", "CLT", "ORD", "MIA", "PHL", "PHX", "LAX", "DCA", "LGA")) |>
        group_by(Origin) |> summarise(flights = sum(flights), late = round(sum(late) / sum(known), 3)) |>
        arrange(desc(late)))
print(cells_ap |> filter(Reporting_Airline == "WN",
                         Origin %in% c("DEN", "LAS", "BWI", "DAL", "MCO", "PHX", "AUS", "BNA", "MDW", "HOU")) |>
        group_by(Origin) |> summarise(flights = sum(flights), late = round(sum(late) / sum(known), 3)) |>
        arrange(desc(late)))

# ---- Figure Q3a: map of volume (size) and late rate (colour) ----
us <- map_data("state")
map_df <- airports |>
  filter(flights >= 10000) |>
  inner_join(mc, by = c("OriginAirportID" = "AIRPORT_ID")) |>
  filter(!AIRPORT_STATE_CODE %in% c("AK", "HI", "PR", "VI", "GU")) |>
  arrange(desc(flights))
cat("Airports on map:", nrow(map_df), "\n")
labels_df <- map_df |> filter(Origin %in% c("DFW", "ORD", "DEN", "ATL", "SLC", "LAX", "SFO", "CLT", "BOS", "MIA", "SEA"))

fig_a <- ggplot() +
  geom_polygon(data = us, aes(long, lat, group = group), fill = "grey95", colour = "white", linewidth = 0.3) +
  geom_point(data = map_df, aes(LONGITUDE, LATITUDE, size = flights, colour = dep_late), alpha = 0.85) +
  geom_text(data = labels_df, aes(LONGITUDE, LATITUDE, label = Origin),
            size = 3, vjust = -1.4, colour = "grey20", fontface = "bold") +
  scale_size_area(max_size = 12, breaks = c(25000, 100000, 300000), labels = scales::comma) +
  scale_colour_distiller(palette = "YlOrRd", direction = 1, labels = scales::percent) +
  coord_quickmap() +
  labs(title = "Where departures leave late: size shows volume, colour shows the late rate",
       subtitle = "Airports with 10,000+ departures in 2025, contiguous US. Departed 15+ min late, share of departures.",
       size = "Departures", colour = "Departed late", x = NULL, y = NULL,
       caption = paste0(src_caption, "\nAirport locations: BTS Master Coordinate table. Alaska, Hawaii and territories not shown.")) +
  theme_group() +
  theme(axis.text = element_blank(), panel.grid = element_blank(),
        legend.key.width = unit(1.2, "cm"))
ggsave("figures/fig_q3a_map.png", fig_a, width = 10, height = 6.5, dpi = 300)

# ---- Figure Q3b: raw vs adjusted late rate for the 30 busiest airports ----
fig_b_data <- top30 |>
  mutate(Origin = factor(Origin, levels = rev(Origin))) |>
  select(Origin, Raw = dep_late, `Adjusted for carrier, month and hour` = adj_late)

fig_b <- ggplot(fig_b_data, aes(y = Origin)) +
  geom_vline(xintercept = national, linetype = "dashed", colour = "grey60") +
  geom_segment(aes(x = Raw, xend = `Adjusted for carrier, month and hour`, yend = Origin), colour = "grey75") +
  geom_point(aes(x = Raw, colour = "Raw"), size = 2.5) +
  geom_point(aes(x = `Adjusted for carrier, month and hour`, colour = "Adjusted for carrier, month and hour"), size = 2.5) +
  scale_x_continuous(labels = scales::percent) +
  scale_colour_manual(values = c(Raw = "grey55", `Adjusted for carrier, month and hour` = pal_main)) +
  labs(title = "After a fair comparison, ORD and DFW stay worst; BWI, MIA and CLT drop down the ranking",
       subtitle = "30 busiest origin airports, 2025, sorted by adjusted rate. Dashed line = national rate (21.8%).",
       x = "Departed 15+ min late", y = NULL, colour = NULL,
       caption = paste0(src_caption, "\nAdjusted = observed / expected x national rate; expected = national rates for the same carrier, month and scheduled hour.")) +
  theme_group()
ggsave("figures/fig_q3b_adjusted.png", fig_b, width = 9, height = 8, dpi = 300)

message("Q3 analysis done. Figures saved to figures/.")
