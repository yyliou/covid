<img src="man/figures/logo.svg" align="right" height="139" alt="twcovid hex logo" />

# twcovid

**twcovid** retrieves Taiwan CDC COVID-19 open data — confirmed cases and
deaths — and reshapes it into analysis-ready tables. A single call to
`tw_covid()` lets the user specify the outcome, the temporal unit, the date
basis, the panel cross-section, and whether to return per-period flows or
cumulative totals, optionally zero-filled into a balanced panel.

The package always retrieves the **daily** source files and performs the
weekly/monthly aggregation, cumulation, and zero-filling internally, so the time
axis is fully controlled and reproducible rather than inherited from
pre-aggregated government tables.

## Features

- **Outcome** (`outcome`): confirmed cases (`"confirmed"`), deaths (`"death"`),
  or both (`"both"`, yielding separate `cases` and `deaths` columns).
- **Temporal unit** (`freq`): day, ISO week (Monday start), or month.
- **Date basis** (`date_type`): for confirmed cases, onset date (發病日) or case
  judgment date (個案研判日); deaths are tabulated by date of death (死亡日).
- **Quantity type** (`cumulative`): per-period incidence (flow) or running
  cumulative totals.
- **Panel cross-section** (`group_by`): any subset of county, township, sex,
  imported status, and age group; omitted dimensions are summed over.
- **Balanced panel** (`balance`): zero-fill so every observed cross-section
  appears in every period of the (optionally clipped) range.

## Installation

```r
# install.packages("devtools")
devtools::load_all(".")            # from within the package directory
# or devtools::install_local("path/to/covid")
```

Dependencies: `readr`, `dplyr`, `tidyr`, `lubridate`, `jsonlite`, `rlang`.

## Usage

```r
library(twcovid)

# Weekly confirmed cases per county (by judgment date; the default):
tw_covid(freq = "week")

# Monthly deaths by date of death, county x age group, balanced panel:
tw_covid(freq = "month", outcome = "death",
         group_by = c("縣市", "年齡層"), balance = TRUE)

# Confirmed cases and deaths together, weekly, national, cumulative:
tw_covid(freq = "week", outcome = "both", group_by = character(0),
         balance = TRUE, cumulative = TRUE)

# By onset date, county x age x sex, with ASCII column names:
tw_covid(freq = "month", date_type = "onset",
         group_by = c("縣市", "年齡層", "性別"),
         start = "2022-01-01", names = "en")
```

The return value is a tibble with one row per cross-section × period: the
`group_by` columns, a `period` column (a `Date` at the start of the day, week,
or month), and the value column(s) `cases` and/or `deaths`.

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `freq` | Temporal unit: `"day"`, `"week"` (ISO week, Monday start), or `"month"`. | `"day"` |
| `outcome` | `"confirmed"` (確定病例數), `"death"` (死亡病例數), or `"both"` (both columns). | `"confirmed"` |
| `date_type` | Date basis for **confirmed** cases: `"judgment"` (個案研判日) or `"onset"` (發病日). Deaths are always by date of death (死亡日). | `"judgment"` |
| `cumulative` | If `TRUE`, report running cumulative totals within each cross-section (ordered by period); best paired with `balance = TRUE`. | `FALSE` |
| `group_by` | Cross-section columns, any subset of `c("縣市", "鄉鎮", "性別", "是否為境外移入", "年齡層")`; omitted columns are summed over. `character(0)` gives a national series. | `"縣市"` |
| `balance` | If `TRUE`, zero-fill to a balanced panel. | `FALSE` |
| `version` | Case-definition file(s): `"both"`, `"19CoV"` (pre-2023/03/19 definition), or `"19CVS"` (current definition). | `"both"` |
| `start`, `end` | Optional date bounds (`Date` or `"YYYY-MM-DD"`) clipping the period axis and any zero-fill. | `NULL` |
| `names` | Cross-section column naming: `"zh"` (Chinese) or `"en"` (county/town/sex/imported/age). Value columns are always `cases`/`deaths`. | `"zh"` |
| `use_api` | If `TRUE`, resolve the current download URL via the open-data API, falling back to built-in URLs. | `TRUE` |
| `cache`, `cache_dir` | Cache downloads (once per day) and where to store them. | `TRUE`, temp dir |

## Flow versus cumulative

By default each row reports the **incidence within that period** (a flow). With
`cumulative = TRUE`, values are replaced by the **running total** within each
cross-section, ordered by period. Cumulative totals are only well defined on a
complete time axis, so `cumulative = TRUE` is normally combined with
`balance = TRUE`; otherwise missing periods displace the cumulative series.

## Balanced panel

With `balance = TRUE` the panel is completed by *nesting*: zeros are inserted
only for cross-sections that actually occur in the data, never for combinations
that never appear. The result is therefore a complete rectangle,

```
nrow == (number of observed cross-sections) × (number of periods),
```

and zero-filling a flow preserves the grand total. The period range defaults to
the observed minimum and maximum; supplying `start`/`end` fixes it explicitly,
which is convenient for aligning all units to a common window.

## The `outcome = "both"` alignment

With `"both"`, confirmed cases (on the chosen `date_type`) and deaths (by date of
death) are aggregated separately and then **outer-joined on `period`**, producing
a table with both `cases` and `deaths`. Because the two series use different
event times (judgment/onset date versus death date), a shared row means only
that the events fall in the same day, week, or month.

## Data sources

| Outcome | Date basis | Source | Daily CSV |
|---------|------------|--------|-----------|
| Confirmed cases | Judgment date | [data.gov.tw 120711](https://data.gov.tw/dataset/120711) | `Day_Confirmation_Age_County_Gender_19CoV.csv` / `…19CVS.csv` |
| Confirmed cases | Onset date | [data.gov.tw 151770](https://data.gov.tw/dataset/151770) | `Age_County_Gender_day_19CoV.csv` / `…19CVS.csv` |
| Deaths | Date of death | [data.cdc.gov.tw death-date-statistics-cases-19cov](https://data.cdc.gov.tw/dataset/death-date-statistics-cases-19cov) | `open_data_death_date_statistics_19CoV_2.csv` / `…19CVS_2.csv` |

Sources are refreshed daily and report through the previous day.
`tw_covid_datasets()` lists every source the package knows about. Downloads are
cached with the download date as the key (one fetch per day);
`tw_covid_clear_cache()` removes the cache.

 **Category encodings (as published).** The source uses coded category values,
not free text: `性別` is `"M"`/`"F"`; `是否為境外移入` is `"1"` (imported) /
`"0"` (domestic); `年齡層` uses ranges such as `"0"`, `"5~9"`, `"55~59"`, `"70+"`;
dates are ISO `"YYYY-MM-DD"`. Filter `group_by` values accordingly (e.g.
`subset(x, 是否為境外移入 == "0")`).

> **Notes.** Imported cases are largely ascertained at airports or quarantine
> facilities and often carry no county information, so their `縣市` field may be an
> empty string; the `鄉鎮` (township) field is likewise empty for many records.
> Filter on `是否為境外移入` as needed. After August 2024, deaths from the
> "新冠併發重症" (severe COVID-19 complications) surveillance scheme are released
> only by **onset week number** (no calendar-date field); the package therefore
> uses the death-by-date-of-death daily table for the death outcome.

## Testing

The pure data transforms (aggregation, zero-filling, cumulation, the `"both"`
merge) are covered by offline `testthat` tests:

```r
devtools::test()
```

These verify that missing-date rows are dropped, totals are conserved across
day/week/month, the balanced panel is a complete rectangle, `start`/`end` clip
the axis correctly, cumulative series are nondecreasing running sums, the
`"both"` merge aligns `cases` and `deaths`, and an empty `group_by` yields a
national series.

> The aggregation logic was validated against an equivalent reference model on
> synthetic data. Run the R `testthat` suite and live downloads locally, where
> CRAN and `od.cdc.gov.tw` are reachable.

## Documentation

The source carries roxygen comments. Regenerate `man/` and synchronise
`NAMESPACE` with `devtools::document()`.

## Extending

To add another table of the same shape (e.g., the weekly severe-complications
death series), append an entry to `.tw_registry` in `R/registry.R` with its date
column, source id (`gov_id` or `cdc_id`), and fallback URLs.
