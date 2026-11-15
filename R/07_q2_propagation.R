# 07_q2_propagation.R
# Q2: How do delays build up through the day, and how much is associated
#     with late-arriving aircraft?
# Input:  data/processed/flights_clean/ (from 04_clean.R)
# Output: figures/fig_q2a_hourly.png
#         figures/fig_q2b_turnaround.png

library(arrow); library(dplyr); library(tidyr); library(ggplot2); library(data.table)
source("R/00_theme.R")

fc <- open_dataset("data/processed/flights_clean")
dir.create("figures", showWarnings = FALSE)

# ---- 1. Late rate and late-aircraft share of delay by scheduled departure hour ----
hourly <- fc |> filter(status == "Completed") |>
  group_by(dep_hour) |>
  summarise(flights = n(), late_rate = mean(ArrDel15, na.rm = TRUE)) |>
  collect()

causes_hour <- fc |> filter(ArrDel15 == 1) |>
  group_by(dep_hour) |>
  summarise(late_aircraft = sum(LateAircraftDelay),
            all_causes    = sum(CarrierDelay + WeatherDelay + NASDelay +
                                SecurityDelay + LateAircraftDelay)) |>
  collect()

hourly <- hourly |> left_join(causes_hour, by = "dep_hour") |>
  mutate(la_share = late_aircraft / all_causes) |> arrange(dep_hour)
print(hourly, n = 24)
cat("Late-aircraft share of all delay minutes:",
    round(sum(hourly$late_aircraft) / sum(hourly$all_causes), 3), "\n")

# ---- 2. Link each flight to the same aircraft's previous flight that day ----
legs <- fc |> filter(status == "Completed", !is.na(Tail_Number)) |>
  select(Month, FlightDate, Tail_Number, carrier_name, Origin, Dest,
         CRSDepTime, CRSArrTime, DepDelay, DepDel15, ArrDelay, ArrDel15) |>
  collect()
setDT(legs)

legs[, dep_min := as.integer(substr(CRSDepTime, 1, 2)) * 60L + as.integer(substr(CRSDepTime, 3, 4))]
legs[, arr_min := as.integer(substr(CRSArrTime, 1, 2)) * 60L + as.integer(substr(CRSArrTime, 3, 4))]
setorder(legs, Tail_Number, FlightDate, dep_min)
legs[, `:=`(prev_dest     = shift(Dest),
            prev_dep      = shift(dep_min),
            prev_arr      = shift(arr_min),
            prev_arrdelay = shift(ArrDelay),
            prev_late     = shift(ArrDel15)),
     by = .(Tail_Number, FlightDate)]

# Valid pairs: previous flight landed where the next one departs, did not cross
# midnight, and the scheduled turnaround is between 1 and 720 minutes.
# Both scheduled times are local to the same airport, so time zones cancel out.
pairs <- legs[!is.na(prev_dest) & prev_dest == Origin & prev_arr >= prev_dep]
pairs[, turn := dep_min - prev_arr]
pairs <- pairs[turn > 0 & turn <= 720 & !is.na(prev_late)]
cat("Completed flights:", nrow(legs), " Linked pairs:", nrow(pairs),
    " Share linked:", round(nrow(pairs) / nrow(legs), 3), "\n")

pairs[, buffer := cut(turn, c(0, 44, 59, 89, 179, 720),
                      labels = c("Under 45", "45-59", "60-89", "90-179", "180+"))]
pairs[, prev_band := cut(prev_arrdelay, c(-Inf, 14, 29, 59, 119, Inf),
                         labels = c("On time (<15)", "15-29", "30-59", "60-119", "120+"))]

# ---- 3. Propagation ----
print(pairs[, .(pairs = .N, next_dep_late = mean(DepDel15), median_next_dep = median(DepDelay)),
            by = prev_late][order(prev_late)])
print(pairs[, .(pairs = .N, next_dep_late = mean(DepDel15)), by = prev_band][order(prev_band)])

by_buffer <- pairs[, .(pairs = .N, next_dep_late = mean(DepDel15)), by = .(buffer, prev_late)][order(buffer, prev_late)]
print(by_buffer)

print(pairs[prev_arrdelay >= 15,
            .(pairs = .N, share_passed_on = mean(pmin(pmax(DepDelay, 0) / prev_arrdelay, 1))),
            by = buffer][order(buffer)])

# ---- 4. Stability: by carrier and by month ----
print(pairs[, .(after_late   = mean(DepDel15[prev_late == 1]),
                after_ontime = mean(DepDel15[prev_late == 0]),
                median_turn  = as.numeric(median(turn)),
                share_under45 = mean(turn < 45)),
            by = carrier_name][order(after_late)])
print(pairs[, .(after_late   = mean(DepDel15[prev_late == 1]),
                after_ontime = mean(DepDel15[prev_late == 0])),
            by = Month][order(Month)])

# ---- Figure Q2a: late rate and late-aircraft share by hour ----
fig_a <- hourly |> filter(flights >= 12000) |>
  select(dep_hour, `Arrived 15+ min late` = late_rate,
         `Late-aircraft share of delay minutes` = la_share) |>
  pivot_longer(-dep_hour, names_to = "measure", values_to = "value") |>
  ggplot(aes(dep_hour, value, colour = measure)) +
  geom_line(linewidth = 0.9) + geom_point(size = 2) +
  scale_x_continuous(breaks = seq(0, 23, 2)) +
  scale_y_continuous(labels = scales::percent, limits = c(0, NA)) +
  scale_colour_manual(values = c(`Arrived 15+ min late` = pal_main,
                                 `Late-aircraft share of delay minutes` = "#E69F00")) +
  labs(title = "Delays build through the day, and more of them are carried over from earlier flights",
       subtitle = "Completed flights by scheduled departure hour (local time), 2025.",
       x = "Scheduled departure hour", y = NULL, colour = NULL,
       caption = paste(src_caption, "Hours 0-4 omitted (fewer than 12,000 flights each).")) +
  theme_group()
ggsave("figures/fig_q2a_hourly.png", fig_a, width = 9, height = 5.5, dpi = 300)

# ---- Figure Q2b: next departure late rate by turnaround buffer ----
fig_b <- ggplot(by_buffer,
                aes(buffer, next_dep_late,
                    fill = factor(prev_late, levels = c(0, 1),
                                  labels = c("Previous flight on time", "Previous flight 15+ min late")))) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  geom_text(aes(label = scales::percent(next_dep_late, accuracy = 1)),
            position = position_dodge(width = 0.8), vjust = -0.4, size = 3.2) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_fill_manual(values = c("grey70", pal_main)) +
  labs(title = "A late inbound flight is usually passed on unless the turnaround has slack",
       subtitle = "Share of next departures leaving 15+ min late, by scheduled time on the ground. Same aircraft, same day.",
       x = "Scheduled turnaround (minutes)", y = "Next flight departed 15+ min late", fill = NULL,
       caption = paste(src_caption, sprintf("%s linked flight pairs.", format(nrow(pairs), big.mark = ",")))) +
  theme_group()
ggsave("figures/fig_q2b_turnaround.png", fig_b, width = 9, height = 5.5, dpi = 300)

message("Q2 analysis done. Figures saved to figures/.")
