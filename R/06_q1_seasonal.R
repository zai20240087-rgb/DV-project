# 06_q1_seasonal.R
# Q1: How do delay and cancellation rates vary across the year?

library(arrow); library(dplyr); library(tidyr); library(ggplot2)

fc <- open_dataset("data/processed/flights_clean")
dir.create("figures", showWarnings = FALSE)
src <- "Source: BTS Reporting Carrier On-Time Performance, 2025 (7,001,619 scheduled flights)"

# 1. Monthly late and cancellation rates
monthly <- fc |> group_by(Month) |>
  summarise(flights   = n(),
            cancelled = sum(Cancelled),
            late      = sum(ArrDel15, na.rm = TRUE),
            arrived   = sum(!is.na(ArrDel15))) |>
  collect() |> arrange(Month) |>
  mutate(cancel_rate = cancelled / flights, late_rate = late / arrived)
print(monthly, n = 12)

# 2. Cancellations by reason and month
reasons <- fc |> filter(Cancelled == 1) |> count(Month, cancel_reason) |> collect() |>
  left_join(select(monthly, Month, flights), by = "Month") |>
  mutate(rate = n / flights) |>
  group_by(Month) |> mutate(share = n / sum(n)) |> ungroup()
print(reasons |> select(Month, cancel_reason, share) |>
        pivot_wider(names_from = cancel_reason, values_from = share) |> arrange(Month), n = 12)

# 3. Full shape of arrival delay by month (completed flights)
dist <- fc |> filter(status == "Completed", !is.na(ArrDelay)) |>
  select(Month, ArrDelay) |> collect() |>
  group_by(Month) |>
  summarise(median = median(ArrDelay), p75 = quantile(ArrDelay, 0.75),
            p90 = quantile(ArrDelay, 0.90), share_60 = mean(ArrDelay >= 60))
print(dist, n = 12)

# 4. Highest-cancellation days (checks the November spike)
daily <- fc |> group_by(FlightDate) |>
  summarise(flights = n(), cancel_rate = mean(Cancelled)) |> collect()
print(daily |> slice_max(cancel_rate, n = 15))
print(daily |> filter(FlightDate >= as.Date("2025-10-25"), FlightDate <= as.Date("2025-11-30")) |>
        arrange(FlightDate), n = 40)

# Figure Q1a: monthly rates
fig_a <- monthly |>
  select(Month, `Arrived 15+ min late (share of flights that arrived)` = late_rate,
         `Cancelled (share of scheduled flights)` = cancel_rate) |>
  pivot_longer(-Month, names_to = "measure", values_to = "rate") |>
  ggplot(aes(Month, rate)) +
  geom_line(colour = "grey50") + geom_point(size = 2) +
  facet_wrap(~ measure, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Late-arrival and cancellation rates by month, 2025",
       subtitle = "US domestic flights. Panels use different y-axis scales.",
       x = NULL, y = NULL, caption = src) +
  theme_minimal(base_size = 12)
ggsave("figures/fig_q1a_monthly_rates.png", fig_a, width = 8, height = 6, dpi = 300)

# Figure Q1b: cancellation rate by reported reason
fig_b <- ggplot(reasons, aes(factor(Month, levels = 1:12, labels = month.abb), rate, fill = cancel_reason)) +
  geom_col() +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "Cancellation rate by carrier-reported reason, by month, 2025",
       x = NULL, y = "Cancelled (share of scheduled flights)", fill = "Reported reason",
       caption = src) +
  theme_minimal(base_size = 12)
ggsave("figures/fig_q1b_cancel_reasons.png", fig_b, width = 9, height = 5, dpi = 300)

# Figure Q1c: delay distribution by month
fig_c <- dist |>
  select(Month, Median = median, `75th percentile` = p75, `90th percentile` = p90) |>
  pivot_longer(-Month, names_to = "statistic", values_to = "minutes") |>
  ggplot(aes(Month, minutes, colour = statistic)) +
  geom_hline(yintercept = 15, linetype = "dashed", colour = "grey60") +
  geom_line() + geom_point(size = 2) +
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  scale_colour_brewer(palette = "Dark2") +
  labs(title = "Arrival delay distribution by month, completed flights, 2025",
       subtitle = "Dashed line = 15-minute 'late' threshold. Negative values = early arrival.",
       x = NULL, y = "Arrival delay (minutes)", colour = NULL, caption = src) +
  theme_minimal(base_size = 12)
ggsave("figures/fig_q1c_delay_distribution.png", fig_c, width = 9, height = 5, dpi = 300)


# ---- Q1 follow-ups ----

# A. What caused the 29 November spike?
print(fc |> filter(FlightDate == as.Date("2025-11-29"), Cancelled == 1) |>
        count(cancel_reason) |> collect())
print(fc |> filter(FlightDate == as.Date("2025-11-29"), Cancelled == 1) |>
        count(Origin, sort = TRUE) |> head(10) |> collect())

# B. Stability check 1: November without the FAA reduction period (7–16 Nov)
nov_check <- fc |> filter(Month == 11) |>
  mutate(period = if_else(FlightDate >= as.Date("2025-11-07") &
                            FlightDate <= as.Date("2025-11-16"),
                          "FAA reductions (7–16 Nov)", "Rest of November")) |>
  group_by(period) |>
  summarise(flights = n(), cancel_rate = mean(Cancelled),
            late_rate = mean(ArrDel15, na.rm = TRUE)) |>
  collect()
print(nov_check)

# C. Stability check 2: does the seasonal pattern hold for most carriers?
by_carrier <- fc |> group_by(carrier_name, Month) |>
  summarise(late_rate = mean(ArrDel15, na.rm = TRUE),
            cancel_rate = mean(Cancelled)) |>
  collect()

carrier_summary <- by_carrier |> group_by(carrier_name) |>
  summarise(
    worst_late_month   = month.abb[Month[which.max(late_rate)]],
    worst_cancel_month = month.abb[Month[which.max(cancel_rate)]],
    jul_late = late_rate[Month == 7],
    sep_late = late_rate[Month == 9],
    summer_higher = jul_late > sep_late
  ) |>
  arrange(carrier_name)
print(carrier_summary, n = 14)
cat("Carriers with July late rate above September:",
    sum(carrier_summary$summer_higher), "of", nrow(carrier_summary), "\n")
print(table(carrier_summary$worst_cancel_month))