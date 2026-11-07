# DV-project — Airline Operational Intelligence (GroupXX)

Group project for Data Exploration and Visualisation, commissioned by OA Aviation Data Intelligence (hypothetical client).

**Main question:** What factors are associated with flight delays in US domestic aviation in 2025?

| Q | Sub-question | Owner |
|---|---|---|
| Q1 | How do delay and cancellation rates vary across the year? | Zaid |
| Q2 | How do delays build up through the day, and how much is associated with late-arriving aircraft? | _name_ |
| Q3 | Where are delays concentrated, and do airport differences remain after accounting for traffic volume, time of day and carrier mix? | _name_ |
| Q4 | Do carriers differ in delays and cancellations after comparing like-for-like, and do they handle disruption differently (cancel vs delay)? | _name_ |

---

## 1. How to reproduce

Requirements: R 4.5.x, RStudio, internet access to BTS TranStats.

1. Clone the repo and open `DV-project.Rproj` in RStudio. All paths are relative to the project root.
2. In the R console: `renv::restore()` (installs the exact package versions in `renv.lock`).
3. Run the scripts in order from a clean R session:

| Script | What it does | Output |
|---|---|---|
| `R/00_theme.R` | Shared figure theme, colours and source caption (sourced by analysis scripts) | — |
| `R/01_download.R` | Downloads the 12 monthly 2025 BTS pre-zipped files | `data/raw/*.zip` |
| `R/02_combine.R` | Unzips each month, keeps selected fields, writes parquet | `data/processed/flights/` |
| `R/03_audit.R` | Data audit and anomaly follow-ups (prints results only) | Console output |
| `R/04_clean.R` | Applies audit decisions; adds derived variables and anomaly flags | `data/processed/flights_clean/` |
| `R/05_overview.R` | Rough exploration plots used to choose the questions (not final figures) | `output/overview/` |
| `R/06_q1_seasonal.R` | Q1 analysis, stability checks and final Q1 figures | `figures/fig_q1*.png` |

`data/` and `output/` are not committed (see `.gitignore`); they are rebuilt from the official source files by the scripts. Raw downloaded files are never edited.

---

## 2. Data source

| Item | Detail |
|---|---|
| Source | U.S. DOT – Bureau of Transportation Statistics (BTS), TranStats |
| Table | Reporting Carrier On-Time Performance (1987–present) |
| Files | `On_Time_Reporting_Carrier_On_Time_Performance_1987_present_2025_1.zip` to `..._2025_12.zip` (pre-zipped monthly files) |
| Period | 1 January – 31 December 2025 |
| Downloaded | 24 October 2026, via `R/01_download.R` |
| Records | 7,001,619 flights (one row = one scheduled nonstop domestic passenger flight) |
| Unit of analysis | Individual flight, aggregated to month, day, carrier or airport as stated per analysis |

### Fields retained (`R/02_combine.R`)

- **Time:** Year, Month, DayofMonth, DayOfWeek, FlightDate
- **Carrier and flight:** Reporting_Airline, Flight_Number_Reporting_Airline, Tail_Number
- **Origin/destination:** OriginAirportID, Origin, OriginCityName, OriginState, OriginCityMarketID, DestAirportID, Dest, DestCityName, DestState, DestCityMarketID, Distance
- **Performance:** CRSDepTime, DepTime, DepDelay, DepDel15, TaxiOut, TaxiIn, CRSArrTime, ArrTime, ArrDelay, ArrDel15, CRSElapsedTime, ActualElapsedTime, AirTime
- **Irregular operations:** Cancelled, CancellationCode, Diverted, CarrierDelay, WeatherDelay, NASDelay, SecurityDelay, LateAircraftDelay

The hhmm time fields (CRSDepTime, DepTime, CRSArrTime, ArrTime) are read as text so leading zeros are kept (e.g. `0545`).

---

## 3. Data audit findings (`R/03_audit.R`)

| Issue | Finding | Decision |
|---|---|---|
| Delay-cause fields 78.1% NA | Exactly the flights not 15+ min late (5,344,846) plus cancelled/diverted (122,135). Every late flight has a cause. | Structural, not missing. Causes analysed only for ArrDel15 = 1 |
| ArrDelay / AirTime / ActualElapsedTime NA (122,135) | = 102,876 cancelled + 19,258 diverted + 1 completed flight | Structural; the 1 completed flight investigated separately |
| DepDelay NA (98,591) | All cancelled; 4,285 cancelled flights departed before cancellation | Structural; "cancelled after departure" kept as a category |
| Empty strings in text fields | CancellationCode, DepTime, ArrTime, Tail_Number use `""` instead of NA | Recoded `""` to NA in `04_clean.R` |
| Duplicates | 0 on FlightDate + carrier + flight number + origin + destination | No action |
| Time format | All hhmm fields 4 characters; "2400" in 747 departures and 3,720 arrivals | "2400" treated as 00:00 when deriving hour. Delays taken from BTS DepDelay/ArrDelay, never recomputed from clock times |
| Extreme values | ArrDelay up to 4,336 min; TaxiOut up to 1,274 min; AirTime min 7 min | Flagged and investigated, not deleted (Section 4) |
| Carriers | 14 reporting carriers; OO, YX, MQ, OH are regionals operating for mainline brands | `is_regional` flag added for fair carrier comparisons |
| Airports | 352 origin airports | Small airports labelled or excluded per analysis where rates are unstable |

---

## 4. Anomaly investigation (`R/03_audit.R` follow-ups)

Outliers are treated as flags, not verdicts. No records were deleted.

| Anomaly | n | Finding | Decision |
|---|---|---|---|
| Completed flight with no arrival data | 1 | YX JFK–MVY, 2025-09-06; departed but no arrival, air time or taxi-in | Kept; `flag_missing_arrival`; excluded from arrival analyses by NA |
| Missing CRSElapsedTime | 2 | Cancelled Hawaiian flights (carrier cause) | No action |
| Empty Tail_Number | 12,501 | All cancelled flights; mostly UA (6,008) and F9 (3,273) | Structural: carriers differ in reporting tails for cancelled flights. Every completed flight has a tail number, so rotation analysis is unaffected |
| Cancelled after departure | 4,285 | 57% weather-coded | Kept as a distinct category |
| DepTime present but DepDelay NA | 421 | All cancelled; OO 389 (92%), G4 18, DL 14; mostly February weather | Carrier reporting practice; treated as cancelled |
| TaxiOut > 300 min | 5 | 4 diverted flights; 1 UA EWR–MCO on 2025-07-14 (379 min) | Kept; `flag_long_taxiout`; diverted flights excluded from taxi-time analysis |
| Implied speed < 100 mph | 180 | Short hub routes (e.g. MKE–ORD, TYR–DFW); consistent with holding/vectoring | Kept; `flag_slow_speed` |
| Implied speed > 650 mph | 56 | Physically implausible; 19 on 2025-03-08 and 2025-11-01 (eves of DST changes), likely timestamp errors | `flag_fast_speed`; AirTime not used for these flights |
| ArrDelay > 6 h / 12 h / 24 h | 24,546 / 7,485 / 643 | Heavy right tail; top 10 days hold only 9% of 12h+ delays; rate varies 0.03–37.8 per 10k flights by carrier | Kept; `flag_extreme_delay` (> 12 h); analysed as part of the distribution |

---

## 5. Cleaning and derived variables (`R/04_clean.R`)

No records removed: the clean dataset has 7,001,619 rows.

| Variable | Definition |
|---|---|
| `status` | Completed / Cancelled / Diverted, from Cancelled and Diverted |
| `cancel_reason` | CancellationCode A–D recoded to Carrier / Weather / NAS / Security |
| `dep_hour`, `arr_hour` | Hour from scheduled CRSDepTime / CRSArrTime (local time); 24 → 0 |
| `carrier_name` | Readable carrier name from Reporting_Airline |
| `is_regional` | TRUE for OO, YX, MQ, OH |
| `route` | `Origin-Dest` |
| `flag_long_taxiout` | TaxiOut > 300 min |
| `flag_fast_speed` | Distance / (AirTime / 60) > 650 mph |
| `flag_slow_speed` | Distance / (AirTime / 60) < 100 mph |
| `flag_extreme_delay` | ArrDelay > 720 min |
| `flag_missing_arrival` | Completed flight with NA ArrDelay |

Flag thresholds are investigation triggers, not exclusion rules.

**Rate definitions used throughout:**
- Late-arrival rate = flights with ArrDel15 = 1 ÷ flights with non-missing ArrDel15 (i.e. flights that arrived).
- Cancellation rate = cancelled flights ÷ all scheduled flights.

---

## 6. Question-specific decisions

### Q1 — Seasonal patterns (`R/06_q1_seasonal.R`)

| Decision | Detail |
|---|---|
| Aggregation | Calendar month; daily level for anomaly checks |
| Delay distribution | Median, 75th and 90th percentile, and share ≥ 60 min of ArrDelay for completed flights |
| Cancellation reasons | Carrier-reported codes; interpreted as recorded category, not verified cause |
| November anomaly | Cancellation rate 5.1% during 7–16 Nov vs 1.2% for the rest of November; these 10 days hold 9,636 of 14,195 November cancellations (68%). Dates match the FAA-ordered flight reductions during the federal government shutdown (started 7 Nov 2025, lifted 17 Nov 2025) — external information, used only to interpret timing, not as proof of cause |
| 29 November spike | 8.4% cancelled; 95% weather-coded; 41% at ORD and MDW. Treated as a local weather event |
| Stability check | Monthly analysis repeated for each of the 14 carriers: all 14 have a higher late rate in July than September; every carrier's worst delay month is Jun, Jul or Dec; September is the best month for 10 of 14 |
| Exclusions | None |

External sources for the November FAA dates: AP, "What to know about 10% reduction in flights at US airports caused by the government shutdown" (7 Nov 2025); ABC News, "FAA lifts order slashing flights, allowing commercial airlines to resume their regular schedules" (Nov 2025).

### Q2 — _to be completed by owner_

### Q3 — _to be completed by owner_ (include the Master Coordinate join: file name, download date, join key)

### Q4 — _to be completed by owner_

---

## 7. Random seeds

No random sampling is used in the analysis pipeline. (`set.seed(42)` was used once to draw a 2,000-flight sample for browsing the data; it does not affect any result.)

---

## 8. Key limitations

- Delay causes and cancellation codes are reported by the carriers themselves; they show the recorded category, not an independently verified cause.
- "Normal" weather is recorded under NAS delay, so WeatherDelay understates the effect of weather.
- Data are observational: findings are associations, not causal effects.
- Coverage is limited to reporting carriers and scheduled nonstop domestic passenger flights (BTS Part 234 scope).
- Times are local; flights crossing midnight or DST changes can produce timestamp errors (see fast-speed flags).
- Carrier reporting practices differ (e.g. tail numbers for cancelled flights, SkyWest cancelled-after-departure records), which can affect carrier comparisons.

---

## 9. Use of AI tools

Claude (Anthropic) was used to help plan the analysis, write and debug R code, and draft and edit report text. All code was run by the group, and all numbers in the report come from the outputs of the scripts in this repository. The group reviewed and is responsible for every analytical decision. _Other members: add any other tools you used._
