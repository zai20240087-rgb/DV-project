# 05_overview.R
# Quick exploration plots to help the group choose intelligence questions.
# Rough plots, NOT final figures. Saved to output/overview/.

library(arrow)
library(dplyr)
library(tidyr)
library(ggplot2)

fc <- open_dataset("data/processed/flights_clean")
completed <- fc |> filter(status == "Completed")
dir.create("output/overview", recursive = TRUE, showWarnings = FALSE)

# 1. Distribution of arrival delay (completed flights, 5-min bins)
dist <- completed |> filter(!is.na(ArrDelay)) |>
  mutate(bin = floor(ArrDelay / 5) * 5) |>
  count(bin) |> collect()

p1 <- ggplot(filter(dist, bin >= -60, bin <= 300), aes(bin, n)) +
  geom_col(width = 5) +
  geom_vline(xintercept = 15, linetype = "dashed", colour = "red") +
  labs(title = "Arrival delay distribution (completed flights)",
       subtitle = "Shown from -60 to 300 min; red line = 15-min 'late' threshold",
       x = "Arrival delay (minutes)", y = "Flights")
ggsave("output/overview/01_delay_distribution.png", p1, width = 9, height = 5)
cat("Share of completed flights > 300 min late:",
    round(100 * sum(dist$n[dist$bin > 300]) / sum(dist$n), 2), "%\n")

# 2. Late and cancellation rates by month
monthly <- fc |> group_by(Month) |>
  summarise(`Late arrival rate` = mean(ArrDel15, na.rm = TRUE),
            `Cancellation rate` = mean(Cancelled)) |>
  collect() |>
  pivot_longer(-Month, names_to = "measure", values_to = "rate")

p2 <- ggplot(monthly, aes(Month, rate)) +
  geom_line() + geom_point() +
  facet_wrap(~ measure, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = 1:12) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Late arrivals and cancellations by month, 2025", x = "Month", y = NULL)
ggsave("output/overview/02_monthly_rates.png", p2, width = 8, height = 6)

# 3. Late rate by scheduled departure hour
hourly <- completed |> group_by(dep_hour) |>
  summarise(flights = n(), late_rate = mean(ArrDel15, na.rm = TRUE)) |>
  collect()

p3 <- ggplot(hourly, aes(dep_hour, late_rate)) +
  geom_col() +
  geom_text(aes(label = round(flights / 1000)), vjust = -0.3, size = 2.5) +
  scale_x_continuous(breaks = 0:23) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Late arrival rate by scheduled departure hour",
       subtitle = "Numbers above bars = thousands of flights",
       x = "Scheduled departure hour (local)", y = "Arrived 15+ min late")
ggsave("output/overview/03_hourly_late_rate.png", p3, width = 9, height = 5)

# 4. Carriers: cancel vs long delay
carrier <- fc |> group_by(carrier_name, is_regional) |>
  summarise(flights      = n(),
            cancel_rate  = mean(Cancelled),
            long_delay   = sum(ArrDelay > 180, na.rm = TRUE) / n(),
            late_rate    = mean(ArrDel15, na.rm = TRUE)) |>
  collect()
print(carrier |> arrange(desc(flights)))

p4 <- ggplot(carrier, aes(cancel_rate, long_delay, size = flights, colour = is_regional)) +
  geom_point(alpha = 0.7) +
  geom_text(aes(label = carrier_name), size = 3, vjust = -1.2, show.legend = FALSE) +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Do carriers cancel or delay?",
       x = "Cancellation rate", y = "Share of flights arriving 3h+ late",
       size = "Flights", colour = "Regional carrier")
ggsave("output/overview/04_carrier_cancel_vs_delay.png", p4, width = 9, height = 6)

# 5. Top 30 busiest origin airports: departure late rate
airports <- fc |> group_by(Origin) |>
  summarise(flights = n(),
            dep_late_rate = mean(DepDel15, na.rm = TRUE),
            cancel_rate   = mean(Cancelled)) |>
  collect() |>
  slice_max(flights, n = 30)

p5 <- ggplot(airports, aes(dep_late_rate, reorder(Origin, dep_late_rate))) +
  geom_col() +
  scale_x_continuous(labels = scales::percent) +
  labs(title = "Departure late rate at the 30 busiest origin airports",
       x = "Departed 15+ min late", y = NULL)
ggsave("output/overview/05_top_airports.png", p5, width = 7, height = 8)

# 6. Delay causes by month (share of delay minutes, late flights only)
causes <- fc |> filter(ArrDel15 == 1) |> group_by(Month) |>
  summarise(Carrier      = sum(CarrierDelay,      na.rm = TRUE),
            Weather      = sum(WeatherDelay,      na.rm = TRUE),
            NAS          = sum(NASDelay,          na.rm = TRUE),
            Security     = sum(SecurityDelay,     na.rm = TRUE),
            LateAircraft = sum(LateAircraftDelay, na.rm = TRUE)) |>
  collect() |>
  pivot_longer(-Month, names_to = "cause", values_to = "minutes")

p6 <- ggplot(causes, aes(factor(Month), minutes, fill = cause)) +
  geom_col(position = "fill") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Share of delay minutes by reported cause, by month",
       subtitle = "Late flights only (ArrDel15 = 1)",
       x = "Month", y = "Share of delay minutes", fill = "Cause")
ggsave("output/overview/06_delay_causes.png", p6, width = 9, height = 5)

message("Overview plots saved to output/overview/")