# ---------------------------------------------------------------------------
# Pure data-frame transforms (no network): standardise -> flow aggregation ->
# optional balanced panel (zero-fill) -> optional cumulative totals. These are
# what the unit tests exercise.
# ---------------------------------------------------------------------------

# Rename the date / value columns to internal names, parse the date, coerce the
# count to integer, and drop rows whose date is missing (some onset dates are
# blank in the source).
.tw_standardize <- function(df, date_col, value_col) {
  if (!date_col %in% names(df)) {
    stop("Expected date column '", date_col, "' not found. Columns: ",
         paste(names(df), collapse = ", "), call. = FALSE)
  }
  if (!value_col %in% names(df)) {
    stop("Expected value column '", value_col, "' not found.", call. = FALSE)
  }
  df$.date  <- lubridate::ymd(df[[date_col]], quiet = TRUE)
  df$.n     <- suppressWarnings(as.integer(df[[value_col]]))
  df$.n[is.na(df$.n)] <- 0L
  df[!is.na(df$.date), , drop = FALSE]
}

# Floor a Date vector to the start of its day / ISO-week (Monday) / month.
.tw_period <- function(date, freq) {
  switch(freq,
    day   = lubridate::floor_date(date, "day"),
    week  = lubridate::floor_date(date, "week", week_start = 1),
    month = lubridate::floor_date(date, "month"),
    stop("freq must be one of 'day', 'week', 'month'.", call. = FALSE)
  )
}

.tw_seq_by <- function(freq) switch(freq, day = "day", week = "week", month = "month")

# Flow aggregation: sum the standardised count by group x period.
# Returns a tibble with the group columns, `period`, and a column named
# `value_name` (e.g. "cases" or "deaths").
.tw_flow <- function(df, freq, group_by, value_name,
                     start = NULL, end = NULL) {
  miss <- setdiff(group_by, names(df))
  if (length(miss)) {
    stop("group_by column(s) not in data: ", paste(miss, collapse = ", "),
         call. = FALSE)
  }
  df$period <- .tw_period(df$.date, freq)
  if (!is.null(start)) df <- df[df$period >= .tw_period(lubridate::as_date(start), freq), , drop = FALSE]
  if (!is.null(end))   df <- df[df$period <= .tw_period(lubridate::as_date(end),   freq), , drop = FALSE]

  out <- dplyr::summarise(
    dplyr::group_by(df, dplyr::across(dplyr::all_of(c(group_by, "period")))),
    !!value_name := sum(.data[[".n"]]),
    .groups = "drop"
  )
  out
}

# Zero-fill to a fully balanced panel: every observed cross-section x every
# period in the (optionally clipped) range. value_cols are filled with 0.
.tw_balance_panel <- function(df, group_by, freq, value_cols,
                              start = NULL, end = NULL) {
  if (nrow(df) == 0) return(df)
  range_start <- if (!is.null(start)) .tw_period(lubridate::as_date(start), freq) else min(df$period)
  range_end   <- if (!is.null(end))   .tw_period(lubridate::as_date(end),   freq) else max(df$period)
  periods <- seq(range_start, range_end, by = .tw_seq_by(freq))
  fill <- stats::setNames(as.list(rep(0L, length(value_cols))), value_cols)

  if (length(group_by) == 0) {
    tidyr::complete(df, period = periods, fill = fill)
  } else {
    tidyr::complete(
      df,
      period = periods,
      tidyr::nesting(!!!rlang::syms(group_by)),
      fill = fill
    )
  }
}

# Running totals of each value column within each cross-section, ordered by
# period. (Most meaningful on a balanced panel.)
.tw_cumulate <- function(df, group_by, value_cols) {
  df <- dplyr::arrange(df, dplyr::across(dplyr::all_of(c(group_by, "period"))))
  if (length(group_by) > 0) df <- dplyr::group_by(df, dplyr::across(dplyr::all_of(group_by)))
  df <- dplyr::mutate(df, dplyr::across(dplyr::all_of(value_cols), cumsum))
  dplyr::ungroup(df)
}
