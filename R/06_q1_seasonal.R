# 06_q1_seasonal.R
# Q1: How do delay and cancellation rates vary across the year?
# Input:  data/processed/flights_clean/ (from 04_clean.R)
# Output: figures/fig_q1a_monthly_rates.png
#         figures/fig_q1b_cancel_reasons.png
#         figures/fig_q1c_delay_distribution.png

library(arrow); library(dplyr); library(tidyr); library(ggplot2)
source("R/00_theme.R")

fc <- open_dataset("data/processed/flights_clean")
dir.create("figures", showWarnings = FALSE)

# ---- 1. Monthly late and cancellation rates ----
monthly <- fc |> group_by(Month) |>
  summarise(flights   = n(),
            cancelled = sum(Cancelled),
            late      = sum(ArrDel15, na.rm = TRUE),
            arrived   = sum(!is.na(ArrDel15))) |>
  collect() |> arrange(Month) |>
  mutate(cancel_rate = cancelled / flights, late_rate = late / arrived)
print(monthly, n = 12)

# ---- 2. Cancellations by reported reason and month ----
reasons <- fc |> filter(Cancelled == 1) |> count(Month, cancel_reason) |> collect() |>
  left_join(select(monthly, Month, flights), by = "Month") |>
  mutate(rate = n / flights) |>
  group_by(Month) |> mutate(share = n / sum(n)) |> ungroup()
print(reasons |> select(Month, cancel_reason, share) |>
        pivot_wider(names_from = cancel_reason, values_from = share) |> arrange(Month), n = 12)

# ---- 3. Full shape of arrival delay by month (completed flights) ----
dist <- fc |> filter(status == "Completed", !is.na(ArrDelay)) |>
  select(Month, ArrDelay) |> collect() |>
  group_by(Month) |>
  summarise(median   = median(ArrDelay),
            p75      = quantile(ArrDelay, 0.75),
            p90      = quantile(ArrDelay, 0.90),
            share_60 = mean(ArrDelay >= 60))
print(dist, n = 12)

# ---- 4. Highest-cancellation days ----
daily <- fc |> group_by(FlightDate) |>
  summarise(flights = n(), cancel_rate = mean(Cancelled)) |> collect()
print(daily |> slice_max(cancel_rate, n = 15))
print(daily |> filter(FlightDate >= as.Date("2025-10-25"), FlightDate <= as.Date("2025-11-30")) |>
        arrange(FlightDate), n = 40)

# ---- 5. Follow-ups: 29 November spike ----
print(fc |> filter(FlightDate == as.Date("2025-11-29"), Cancelled == 1) |>
        count(cancel_reason) |> collect())
print(fc |> filter(FlightDate == as.Date("2025-11-29"), Cancelled == 1) |>
        count(Origin, sort = TRUE) |> head(10) |> collect())

# ---- 6. Stability check: November with vs without FAA reduction period (7-16 Nov) ----
nov_check <- fc |> filter(Month == 11) |>
  mutate(period = if_else(FlightDate >= as.Date("2025-11-07") &
                            FlightDate <= as.Date("2025-11-16"),
                          "FAA reductions (7-16 Nov)", "Rest of November")) |>
  group_by(period) |>
  summarise(flights = n(), cancelled = sum(Cancelled),
            cancel_rate = mean(Cancelled),
            late_rate = mean(ArrDel15, na.rm = TRUE)) |>
  collect()
print(nov_check)

# ---- 7. Stability check: does the seasonal pattern hold for every carrier? ----
by_carrier <- fc |> group_by(carrier_name, Month) |>
  summarise(late_rate = mean(ArrDel15, na.rm = TRUE),
            cancel_rate = mean(Cancelled)) |>
  collect()

carrier_summary <- by_carrier |> group_by(carrier_name) |>
  summarise(worst_late_month   = month.abb[Month[which.max(late_rate)]],
            best_late_month    = month.abb[Month[which.min(late_rate)]],
            worst_cancel_month = month.abb[Month[which.max(cancel_rate)]],
            jul_late = late_rate[Month == 7],
            sep_late = late_rate[Month == 9],
            summer_higher = jul_late > sep_late) |>
  arrange(carrier_name)
print(carrier_summary, n = 14)
cat("Carriers with July late rate above September:",
    sum(carrier_summary$summer_higher), "of", nrow(carrier_summary), "\n")
print(table(carrier_summary$worst_late_month))
print(table(carrier_summary$best_late_month))
print(table(carrier_summary$worst_cancel_month))

# ---- Figure Q1a: monthly rates, with the FAA period labelled ----
fig_a_data <- monthly |>
  select(Month, `Arrived 15+ min late (share of flights that arrived)` = late_rate,
         `Cancelled (share of scheduled flights)` = cancel_rate) |>
  pivot_longer(-Month, names_to = "measure", values_to = "rate")

faa_label <- data.frame(Month = 11, rate = monthly$cancel_rate[11],
                        measure = "Cancelled (share of scheduled flights)",
                        label = "FAA flight cuts\n7-16 Nov")

fig_a <- ggplot(fig_a_data, aes(Month, rate)) +
  geom_line(colour = "grey60") +
  geom_point(size = 2.5, colour = pal_main) +
  geom_text(data = faa_label, aes(label = label), hjust = 1.15, size = 3.3, colour = "grey30") +
  facet_wrap(~ measure, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Delays peak in summer and December; cancellations in January, July and November",
       subtitle = "US domestic flights by month, 2025. Panels use different y-axis scales.",
       x = NULL, y = NULL, caption = src_caption) +
  theme_group()
ggsave("figures/fig_q1a_monthly_rates.png", fig_a, width = 9, height = 6.5, dpi = 300)

# ---- Figure Q1b: cancellation rate by reported reason ----
fig_b <- ggplot(reasons, aes(factor(Month, levels = 1:12, labels = month.abb), rate, fill = cancel_reason)) +
  geom_col() +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_manual(values = pal_reason) +
  labs(title = "Weather drives most cancellations, except in November",
       subtitle = "Cancellation rate by carrier-reported reason, 2025. November's peak is mostly coded as airspace system (NAS).",
       x = NULL, y = "Cancelled (share of scheduled flights)", fill = "Reported reason",
       caption = paste(src_caption, "Security cancellations are under 0.3% in every month and not visible.")) +
  theme_group()
ggsave("figures/fig_q1b_cancel_reasons.png", fig_b, width = 9, height = 5.5, dpi = 300)

# ---- Figure Q1c: arrival delay distribution by month ----
fig_c <- dist |>
  select(Month, Median = median, `75th percentile` = p75, `90th percentile` = p90) |>
  pivot_longer(-Month, names_to = "statistic", values_to = "minutes") |>
  mutate(statistic = factor(statistic, levels = c("Median", "75th percentile", "90th percentile"))) |>
  ggplot(aes(Month, minutes, colour = statistic)) +
  geom_hline(yintercept = 15, linetype = "dashed", colour = "grey60") +
  geom_line() + geom_point(size = 2) +
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  scale_colour_manual(values = c(Median = "grey50", `75th percentile` = "#56B4E9",
                                 `90th percentile` = "#0072B2")) +
  labs(title = "Peak months bring more long delays, not just more slightly late flights",
       subtitle = "Arrival delay percentiles for completed flights, 2025. Dashed line = 15-minute 'late' threshold; negative = early.",
       x = NULL, y = "Arrival delay (minutes)", colour = NULL, caption = src_caption) +
  theme_group()
ggsave("figures/fig_q1c_delay_distribution.png", fig_c, width = 9, height = 5.5, dpi = 300)

message("Q1 analysis done. Figures saved to figures/.")