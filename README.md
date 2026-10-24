# DV-project
## Data audit findings (03_audit.R)
| Issue | Finding | Decision |
|---|---|---|
| Delay-cause fields 78.1% NA | Exactly = flights not 15+ min late, plus cancelled/diverted | Structural, not missing. Analyse causes only for ArrDel15 = 1 |
| ArrDelay/AirTime NA (122,135) | = cancelled + diverted + 1 completed flight | Structural; 1 completed flight investigated separately |
| DepDelay NA (98,591) | All cancelled; 4,285 cancelled flights had departed | Structural; keep as "cancelled after departure" category |
| Empty strings in text fields | CancellationCode, DepTime, ArrTime use "" | Recode "" to NA in cleaning script |
| Tail_Number empty (12,501) | Genuinely missing | Kept; excluded only from aircraft-rotation analysis |
| Duplicates | 0 on date + carrier + flight no. + route | No action |
| "2400" times | 747 dep, 3,720 arr | Treated as 00:00 when deriving hour; delays taken from BTS fields, not recomputed |
| Extreme values | Delays to 4,336 min, TaxiOut to 1,274 min, AirTime min 7 | Flagged and investigated, not deleted (see anomaly log) |
| Regional carriers | OO, YX, MQ, OH operate for mainline brands | Noted for fair carrier comparisons |
