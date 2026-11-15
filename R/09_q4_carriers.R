# 09_q4_carriers.R
# Q4: Do carriers differ in delays and cancellations after comparing
#     like-for-like, and do they handle disruption differently (cancel vs delay)?
# Input:  data/processed/flights_clean/ (from 04_clean.R)
# Output: figures/fig_q4a_adjusted.png
#         figures/fig_q4b_cancel_vs_delay.png

library(arrow); library(dplyr); library(tidyr); library(ggplot2)
source("R/00_theme.R")

fc <- open_dataset("data/processed/flights_clean")
dir.create("figures", showWarnings = FALSE)

# ---- 1. Carrier disruption profile (raw) ----
profile <- fc |>
  group_by(carrier_name, is_regional) |>
  summarise(flights      = n(),
            late_rate    = mean(ArrDel15, na.rm = TRUE),
            cancel_rate  = mean(Cancelled),
            divert_rate  = mean(Diverted),
            disrupted    = mean(if_else(coalesce(ArrDel15, 0) == 1 | Cancelled == 1 | Diverted == 1, 1, 0)),
            late_3h      = sum(ArrDelay > 180, na.rm = TRUE) / n(),
            per10k_12h   = 10000 * sum(ArrDelay > 720, na.rm = TRUE) / n()) |>
  collect() |> arrange(late_rate)
print(profile, n = 14, width = Inf)

# ---- 2. Fair comparison: same airport, month and scheduled hour ----
cells_c <- fc |>
  group_by(carrier_name, Origin, Month, dep_hour) |>
  summarise(flights = n(), arrived = sum(!is.na(ArrDel15)),
            late = sum(ArrDel15, na.rm = TRUE), cancelled = sum(Cancelled)) |>
  collect()

cells <- cells_c |>
  group_by(Origin, Month, dep_hour) |>
  summarise(e_late = sum(late) / sum(arrived), e_canc = sum(cancelled) / sum(flights), .groups = "drop")

nat_late <- sum(cells_c$late) / sum(cells_c$arrived)
nat_canc <- sum(cells_c$cancelled) / sum(cells_c$flights)

adjusted <- cells_c |>
  left_join(cells, by = c("Origin", "Month", "dep_hour")) |>
  group_by(carrier_name) |>
  summarise(raw_late  = sum(late) / sum(arrived),
            exp_late  = sum(arrived * e_late, na.rm = TRUE) / sum(arrived),
            raw_canc  = sum(cancelled) / sum(flights),
            exp_canc  = sum(flights * e_canc) / sum(flights),
            .groups = "drop") |>
  mutate(adj_late = raw_late / exp_late * nat_late,
         adj_canc = raw_canc / exp_canc * nat_canc,
         raw_rank = rank(raw_late), adj_rank = rank(adj_late)) |>
  arrange(adj_late)
print(adjusted |> mutate(across(where(is.double), ~ round(.x, 4))), n = 14, width = Inf)

# ---- 3. Stability: adjusted late-rate rank by month ----
monthly <- cells_c |>
  left_join(cells, by = c("Origin", "Month", "dep_hour")) |>
  group_by(carrier_name, Month) |>
  summarise(oe = (sum(late) / sum(arrived)) / (sum(arrived * e_late, na.rm = TRUE) / sum(arrived)),
            .groups = "drop") |>
  group_by(Month) |> mutate(rank = rank(oe)) |> ungroup()
print(monthly |> group_by(carrier_name) |>
        summarise(best = min(rank), worst = max(rank), median_rank = median(rank),
                  top3_months = sum(rank <= 3), bottom3_months = sum(rank >= 12)) |>
        arrange(median_rank), n = 14)

# ---- 4. High-disruption days: top 5% of days by national cancellation rate ----
daily <- fc |> group_by(FlightDate) |>
  summarise(cancel_rate = mean(Cancelled), late_rate = mean(ArrDel15, na.rm = TRUE)) |>
  collect()
threshold <- quantile(daily$cancel_rate, 0.95)
bad_days  <- daily$FlightDate[daily$cancel_rate >= threshold]
cat("High-disruption days:", length(bad_days), " threshold:", round(threshold, 4), "\n")
print(daily |> filter(FlightDate %in% bad_days) |> arrange(desc(cancel_rate)), n = 30)

on_bad <- fc |>
  mutate(bad = FlightDate %in% bad_days) |>
  group_by(carrier_name, is_regional, bad) |>
  summarise(cancel_rate = mean(Cancelled),
            late_3h     = sum(ArrDelay > 180, na.rm = TRUE) / n()) |>
  collect()
print(on_bad |> pivot_wider(names_from = bad, values_from = c(cancel_rate, late_3h)) |>
        arrange(cancel_rate_TRUE), n = 14, width = Inf)

# ---- 5. Regional vs mainline at the same airport on the same day ----
airport_day <- fc |>
  group_by(Origin, FlightDate, is_regional) |>
  summarise(flights = n(), cancelled = sum(Cancelled)) |>
  collect() |>
  mutate(type = if_else(is_regional, "reg", "main")) |>
  select(-is_regional) |>
  pivot_wider(names_from = type, values_from = c(flights, cancelled)) |>
  filter(!is.na(flights_reg), !is.na(flights_main)) |>
  mutate(day_rate = (cancelled_reg + cancelled_main) / (flights_reg + flights_main),
         band = cut(day_rate, c(-Inf, 0.02, 0.10, Inf), right = FALSE,
                    labels = c("Normal (<2% cancelled)", "Disrupted (2-10%)", "Severe (10%+)")))

regional_vs_main <- airport_day |>
  group_by(band) |>
  summarise(airport_days = n(),
            regional_cancel = sum(cancelled_reg) / sum(flights_reg),
            mainline_cancel = sum(cancelled_main) / sum(flights_main)) |>
  mutate(ratio = regional_cancel / mainline_cancel)
print(regional_vs_main)

# ---- Figure Q4a: raw vs adjusted late rate by carrier ----
fig_a_data <- adjusted |>
  mutate(carrier_name = factor(carrier_name, levels = rev(carrier_name))) |>
  select(carrier_name, Raw = raw_late, `Adjusted for airport, month and hour` = adj_late)

fig_a <- ggplot(fig_a_data, aes(y = carrier_name)) +
  geom_vline(xintercept = nat_late, linetype = "dashed", colour = "grey60") +
  geom_segment(aes(x = Raw, xend = `Adjusted for airport, month and hour`, yend = carrier_name), colour = "grey75") +
  geom_point(aes(x = Raw, colour = "Raw"), size = 2.8) +
  geom_point(aes(x = `Adjusted for airport, month and hour`, colour = "Adjusted for airport, month and hour"), size = 2.8) +
  scale_x_continuous(labels = scales::percent) +
  scale_colour_manual(values = c(Raw = "grey55", `Adjusted for airport, month and hour` = pal_main)) +
  labs(title = "Compared like-for-like, Hawaiian drops from best to worst and Envoy moves to the top",
       subtitle = sprintf("Arrived 15+ min late, by carrier, 2025, sorted by adjusted rate. Dashed line = national rate (%s).",
                          scales::percent(nat_late, accuracy = 0.1)),
       x = "Arrived 15+ min late", y = NULL, colour = NULL,
       caption = paste0(src_caption, "\nAdjusted = observed / expected x national rate; expected = national rates for the same origin airport, month and scheduled hour.")) +
  theme_group()
ggsave("figures/fig_q4a_adjusted.png", fig_a, width = 9, height = 6, dpi = 300)

# ---- Figure Q4b: cancel or delay on the worst days ----
fig_b_data <- on_bad |> filter(bad) |>
  mutate(type = if_else(is_regional, "Regional carrier", "Mainline / low-cost carrier"))

fig_b <- ggplot(fig_b_data, aes(cancel_rate, late_3h, colour = type)) +
  geom_point(size = 3.5) +
  geom_text(aes(label = carrier_name), vjust = -1.1, size = 3.2, show.legend = FALSE) +
  scale_x_continuous(labels = scales::percent, expand = expansion(mult = c(0.05, 0.12))) +
  scale_y_continuous(labels = scales::percent, expand = expansion(mult = c(0.05, 0.15))) +
  scale_colour_manual(values = c(`Regional carrier` = "#E69F00", `Mainline / low-cost carrier` = pal_main)) +
  labs(title = "On the worst days, Republic, PSA and Envoy cancel heavily while Allegiant flies very late instead",
       subtitle = sprintf("The %d days with the highest national cancellation rates in 2025 (top 5%%, at least %s cancelled).",
                          length(bad_days), scales::percent(threshold, accuracy = 0.1)),
       x = "Cancelled (share of scheduled flights)", y = "Arrived 3+ hours late (share of scheduled flights)",
       colour = NULL, caption = src_caption) +
  theme_group()
ggsave("figures/fig_q4b_cancel_vs_delay.png", fig_b, width = 9, height = 6, dpi = 300)

message("Q4 analysis done. Figures saved to figures/.")
