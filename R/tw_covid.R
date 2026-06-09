# ---------------------------------------------------------------------------
# Fetch helpers + the user-facing tw_covid() / tw_covid_raw()
# ---------------------------------------------------------------------------

# Download every requested version for one date_type entry and bind them,
# tagging each row with `.version`. In version = "both" mode a single failing
# version is downgraded to a warning as long as the other succeeds.
.tw_fetch_entry <- function(entry, version, use_api, cache, cache_dir) {
  urls <- .tw_resolve_urls(entry, version, use_api = use_api)
  if (length(urls) == 0) {
    stop("No download URL resolved for this dataset / version.", call. = FALSE)
  }
  errs <- character(0)
  parts <- lapply(names(urls), function(v) {
    d <- tryCatch(
      .tw_download_csv(urls[[v]], cache = cache, cache_dir = cache_dir),
      error = function(e) {
        errs[[v]] <<- conditionMessage(e)
        if (identical(version, "both")) {
          warning("Skipping version '", v, "': ", conditionMessage(e), call. = FALSE)
          return(NULL)
        }
        stop(e)
      }
    )
    if (is.null(d)) return(NULL)
    d$.version <- v
    d
  })
  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0) {
    stop("All version downloads failed:\n",
         paste0("  - ", names(errs), ": ", unlist(errs), collapse = "\n"),
         call. = FALSE)
  }
  dplyr::bind_rows(parts)
}

# Resolve the date_type entry for an outcome, auto-selecting for death.
.tw_entry <- function(outcome, date_type) {
  o <- .tw_registry[[outcome]]
  dts <- names(o$date_types)
  dt  <- if (outcome == "death") dts[[1]] else date_type
  if (!dt %in% dts) {
    stop("date_type '", dt, "' is not available for outcome '", outcome,
         "'. Available: ", paste(dts, collapse = ", "), call. = FALSE)
  }
  list(outcome = o, entry = o$date_types[[dt]], date_type = dt)
}

#' Fetch raw Taiwan COVID-19 daily open data
#'
#' Downloads the unmodified daily CSV(s) for one outcome / date type and binds
#' the requested case-definition version(s) together, adding a `.version`
#' column. Mostly for debugging; most users want [tw_covid()].
#'
#' @param outcome "confirmed" (確定病例) or "death" (死亡病例).
#' @param date_type "judgment" (個案研判日) or "onset" (發病日) for confirmed
#'   cases; deaths are always by 死亡日 and this is ignored.
#' @param version "both" (default), "19CoV", or "19CVS".
#' @param use_api,cache,cache_dir See [tw_covid()].
#' @return A tibble of raw rows with an added `.version` column.
#' @export
tw_covid_raw <- function(outcome = c("confirmed", "death"),
                         date_type = c("judgment", "onset"),
                         version = c("both", "19CoV", "19CVS"),
                         use_api = TRUE, cache = TRUE, cache_dir = NULL) {
  outcome   <- match.arg(outcome)
  date_type <- match.arg(date_type)
  version   <- match.arg(version)
  sel <- .tw_entry(outcome, date_type)
  .tw_fetch_entry(sel$entry, version, use_api, cache, cache_dir)
}

# Produce one outcome's flow table: group_by + period + value_name.
.tw_outcome_flow <- function(outcome, date_type, freq, group_by, version,
                             start, end, use_api, cache, cache_dir) {
  sel <- .tw_entry(outcome, date_type)
  raw <- .tw_fetch_entry(sel$entry, version, use_api, cache, cache_dir)
  std <- .tw_standardize(raw, sel$entry$date_col, sel$outcome$value_col)
  .tw_flow(std, freq = freq, group_by = group_by,
           value_name = sel$outcome$value_name, start = start, end = end)
}

#' Fetch and aggregate Taiwan COVID-19 case / death counts
#'
#' One call to download Taiwan CDC COVID-19 open data and reshape it for
#' analysis. Choose the outcome (confirmed cases / deaths / both), the time unit
#' (day / week / month), the date basis, the panel cross-section, whether to
#' zero-fill into a balanced panel, and whether to report period flows or
#' running cumulative totals.
#'
#' @param freq Time unit: `"day"`, `"week"` (ISO week, Monday start), or
#'   `"month"`. Aggregated from the daily source.
#' @param outcome `"confirmed"` (確定病例數, default), `"death"` (死亡病例數), or
#'   `"both"`. With `"both"` the result has both a `cases` and a `deaths`
#'   column.
#' @param date_type Date basis for **confirmed** cases: `"judgment"`
#'   (個案研判日, default) or `"onset"` (發病日). Deaths are always by 死亡日.
#' @param group_by Character vector of categorical columns defining the panel
#'   cross-section. Any subset of `c("縣市", "鄉鎮", "性別",
#'   "是否為境外移入", "年齡層")`. Columns not listed are summed over.
#'   `character(0)` gives a national series. Default `"縣市"`.
#' @param balance If `TRUE`, zero-fill so every observed cross-section appears in
#'   every period across the (filtered) range — a balanced panel. Default
#'   `FALSE`.
#' @param cumulative If `TRUE`, report running cumulative totals within each
#'   cross-section (ordered by period) instead of per-period flows. Best paired
#'   with `balance = TRUE`. Default `FALSE`.
#' @param version Case-definition file(s): `"both"` (default), `"19CoV"`
#'   (pre-2023/03/19 definition), or `"19CVS"` (current). See
#'   [tw_covid_datasets()].
#' @param start,end Optional date bounds (Date or "YYYY-MM-DD"); clip the period
#'   axis and any zero-fill.
#' @param names Column naming for the cross-section: `"zh"` (Chinese, default) or
#'   `"en"` (county/town/sex/imported/age). Value columns are always `cases` /
#'   `deaths`.
#' @param use_api,cache,cache_dir Downloader options; see [tw_covid_raw()].
#'
#' @return A tibble: one row per cross-section x period, with the `group_by`
#'   columns, `period` (a Date at the start of the day/week/month), and the
#'   value column(s) `cases` and/or `deaths`.
#'
#' @examples
#' \dontrun{
#' # Weekly confirmed cases per county:
#' tw_covid(freq = "week")
#'
#' # Monthly deaths by death date, county x age, balanced panel:
#' tw_covid(freq = "month", outcome = "death",
#'          group_by = c("縣市", "年齡層"), balance = TRUE)
#'
#' # Both outcomes, weekly, national, cumulative running totals:
#' tw_covid(freq = "week", outcome = "both", group_by = character(0),
#'          balance = TRUE, cumulative = TRUE)
#' }
#' @export
tw_covid <- function(freq = c("day", "week", "month"),
                     outcome = c("confirmed", "death", "both"),
                     date_type = c("judgment", "onset"),
                     group_by = "縣市",
                     balance = FALSE,
                     cumulative = FALSE,
                     version = c("both", "19CoV", "19CVS"),
                     start = NULL, end = NULL,
                     names = c("zh", "en"),
                     use_api = TRUE, cache = TRUE, cache_dir = NULL) {
  freq      <- match.arg(freq)
  outcome   <- match.arg(outcome)
  date_type <- match.arg(date_type)
  version   <- match.arg(version)
  names     <- match.arg(names)

  group_by <- group_by %||% character(0)
  bad <- setdiff(group_by, .tw_group_cols)
  if (length(bad)) {
    stop("group_by may only contain: ", paste(.tw_group_cols, collapse = ", "),
         "\nUnknown: ", paste(bad, collapse = ", "), call. = FALSE)
  }

  outcomes <- if (identical(outcome, "both")) c("confirmed", "death") else outcome

  flows <- lapply(outcomes, function(oc) {
    .tw_outcome_flow(oc, date_type, freq, group_by, version,
                     start, end, use_api, cache, cache_dir)
  })

  by <- c(group_by, "period")
  out <- Reduce(function(a, b) dplyr::full_join(a, b, by = by), flows)

  value_cols <- vapply(outcomes, function(oc) .tw_registry[[oc]]$value_name, character(1))
  out <- tidyr::replace_na(out, stats::setNames(as.list(rep(0L, length(value_cols))), value_cols))

  if (balance)    out <- .tw_balance_panel(out, group_by, freq, value_cols, start, end)
  if (cumulative) out <- .tw_cumulate(out, group_by, value_cols)

  out <- dplyr::arrange(out, dplyr::across(dplyr::all_of(by)))
  out <- dplyr::relocate(out, dplyr::all_of(group_by), "period", dplyr::all_of(value_cols))

  if (identical(names, "en")) {
    ren <- .tw_name_map[base::names(.tw_name_map) %in% colnames(out)]
    out <- dplyr::rename_with(out, ~ unname(.tw_name_map[.x]),
                              .cols = dplyr::all_of(base::names(ren)))
  }
  out
}
