# twcovid <img src="man/figures/logo.svg" align="right" height="139" alt="twcovid hex logo" />

## 1. Overview

`twcovid` retrieves Taiwan CDC COVID-19 open data — confirmed cases and deaths —
and reshapes it into analysis-ready tables. A single call to `tw_covid()` lets
the user specify the outcome, the temporal unit, the date basis, the panel
cross-section, and whether to return per-period flows or cumulative totals,
optionally zero-filled into a balanced panel.

The package always retrieves the **daily** source files and performs the
weekly/monthly aggregation, cumulation, and zero-filling internally, so the time
axis is fully controlled and reproducible rather than inherited from
pre-aggregated government tables.

```r
# install.packages("remotes")
remotes::install_github("yyliou/covid")
```

Dependencies: `readr`, `dplyr`, `tidyr`, `lubridate`, `jsonlite`, `rlang`.

## 2. Functions

| Function | Purpose |
|---|---|
| `tw_covid()` | Main function: download, aggregate, and reshape case/death counts into a tidy panel. |
| `tw_covid_raw()` | Return the unmodified daily CSV(s) for one outcome/date type (debugging). |
| `tw_covid_datasets()` | List every outcome × date-type source the package knows about. |
| `tw_covid_clear_cache()` | Remove the download cache. |

## 3. Arguments (`tw_covid()`)

| Argument | Description | Default |
|---|---|---|
| `freq` | Temporal unit: `"day"`, `"week"` (ISO week, Monday start), or `"month"`. | `"day"` |
| `outcome` | `"confirmed"` (確定病例數), `"death"` (死亡病例數), or `"both"` (both columns). | `"confirmed"` |
| `date_type` | Date basis for **confirmed** cases: `"judgment"` (個案研判日) or `"onset"` (發病日). Deaths are always by date of death (死亡日). | `"judgment"` |
| `group_by` | Cross-section columns; any subset of `c("縣市", "鄉鎮", "性別", "是否為境外移入", "年齡層")`. Omitted columns are summed over; `character(0)` gives a national series. | `"縣市"` |
| `balance` | If `TRUE`, zero-fill into a balanced panel (every observed cross-section in every period). | `FALSE` |
| `cumulative` | If `TRUE`, report running cumulative totals within each cross-section (best paired with `balance = TRUE`). | `FALSE` |
| `version` | Case-definition file(s): `"both"`, `"19CoV"` (pre-2023/03/19 definition), or `"19CVS"` (current). | `"both"` |
| `start`, `end` | Optional date bounds (`Date` or `"YYYY-MM-DD"`) clipping the period axis and any zero-fill. | `NULL` |
| `names` | Cross-section column naming: `"zh"` (Chinese) or `"en"` (county/town/sex/imported/age). | `"zh"` |
| `use_api` | If `TRUE`, resolve the current download URL via the open-data API, falling back to built-in URLs. | `TRUE` |
| `cache`, `cache_dir` | Cache downloads (once per day) and where to store them. | `TRUE`, temp dir |

`tw_covid_raw()` shares the `outcome`, `date_type`, `version`, `use_api`,
`cache`, and `cache_dir` arguments.

## 4. Output codebook

`tw_covid()` returns a tibble with one row per cross-section × period:

| Column | Type | Description |
|---|---|---|
| *group-by columns* | character | The `group_by` dimensions requested (Chinese or English names per `names`). |
| `period` | Date | Start of the day, ISO week (Monday), or month. |
| `cases` | integer | Confirmed-case count (present when `outcome` is `"confirmed"` or `"both"`). |
| `deaths` | integer | Death count (present when `outcome` is `"death"` or `"both"`). |

With `cumulative = TRUE` the value columns hold running totals within each
cross-section instead of per-period flows. With `outcome = "both"`, cases (on the
chosen `date_type`) and deaths (by death date) are aggregated separately and
outer-joined on `period`; a shared row only means the events fall in the same
period.

**Category encodings (as published).** `性別` is `"M"`/`"F"`; `是否為境外移入`
is `"1"` (imported) / `"0"` (domestic); `年齡層` uses ranges such as `"0"`,
`"5~9"`, `"55~59"`, `"70+"`; dates are ISO `"YYYY-MM-DD"`.

## 5. Examples

```r
library(twcovid)

# Weekly confirmed cases per county (judgment date; the default):
tw_covid(freq = "week")

# Monthly deaths by date of death, county x age group, balanced panel:
tw_covid(freq = "month", outcome = "death",
         group_by = c("縣市", "年齡層"), balance = TRUE)

# Confirmed cases and deaths together, weekly, national, cumulative:
tw_covid(freq = "week", outcome = "both", group_by = character(0),
         balance = TRUE, cumulative = TRUE)

# By onset date, county x age x sex, from 2022, with ASCII column names:
tw_covid(freq = "month", date_type = "onset",
         group_by = c("縣市", "年齡層", "性別"),
         start = "2022-01-01", names = "en")
```

## 6. Notes

- **Imported cases** are largely ascertained at airports/quarantine facilities
  and often carry no county information, so `縣市` may be an empty string; `鄉鎮`
  is likewise empty for many records. Filter on `是否為境外移入` as needed.
- **Balanced panel** zero-fills by *nesting*: zeros are inserted only for
  cross-sections that actually occur, so the result is a complete rectangle
  (`nrow == observed cross-sections × periods`) and the grand total is preserved.
- **Death series** uses the by-date-of-death daily file (`…_2.csv`, which has a
  real `死亡日` column); the `…_3.csv` files are tabulated only by death-week
  number and are not used.
- **TLS workaround.** `od.cdc.gov.tw` omits an intermediate certificate, so a
  verified download may fail. The package retries once without verification (the
  certificate is otherwise browser-trusted) and warns; silence with
  `options(twcovid.insecure = TRUE)`. Behind a proxy, set
  `Sys.setenv(https_proxy = "http://host:port")`.

## 7. Data sources & citation

| Outcome | Date basis | Source | Daily CSV |
|---|---|---|---|
| Confirmed cases | Judgment date | [data.gov.tw 120711](https://data.gov.tw/dataset/120711) | `Day_Confirmation_Age_County_Gender_19CoV.csv` / `…19CVS.csv` |
| Confirmed cases | Onset date | [data.gov.tw 151770](https://data.gov.tw/dataset/151770) | `Age_County_Gender_day_19CoV.csv` / `…19CVS.csv` |
| Deaths | Date of death | [data.cdc.gov.tw](https://data.cdc.gov.tw/dataset/death-date-statistics-cases-19cov) | `open_data_death_date_statistics_19CoV_2.csv` / `…19CVS_2.csv` |

Data © Taiwan Centers for Disease Control (CDC), released as government open
data; please observe the provider's open-data terms when redistributing.
`tw_covid_datasets()` lists every source the package knows about.
