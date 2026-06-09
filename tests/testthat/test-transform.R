# Pure-transform tests (no network). Mirror the reference algorithm:
# missing dates dropped, totals conserved across freq, balanced panel is a full
# rectangle, cumulative totals are running sums, and "both" merges cases+deaths
# onto a shared grid.

confirmed_raw <- function() {
  data.frame(
    確定病名 = "肺炎",
    個案研判日 = c("2022/01/01", "2022/01/01", "2022/01/03",
                   "2022/01/10", "2022/02/15", ""),  # last: missing date
    縣市 = c("臺北市", "臺北市", "臺北市", "新北市", "臺北市", "臺北市"),
    鄉鎮 = "",
    性別 = c("男", "女", "男", "女", "男", "男"),
    是否為境外移入 = c("否", "否", "否", "是", "否", "否"),
    年齡層 = c("20-29", "30-39", "20-29", "40-49", "20-29", "20-29"),
    確定病例數 = c("3", "2", "5", "1", "4", "9"),
    stringsAsFactors = FALSE
  )
}

grp4 <- c("縣市", "性別", "是否為境外移入", "年齡層")

test_that("standardize parses dates, coerces counts, drops missing dates", {
  std <- twcovid:::.tw_standardize(confirmed_raw(), "個案研判日", "確定病例數")
  expect_equal(nrow(std), 5L)
  expect_equal(sum(std$.n), 15L)
  expect_s3_class(std$.date, "Date")
})

test_that("flow totals are conserved across day / week / month", {
  std <- twcovid:::.tw_standardize(confirmed_raw(), "個案研判日", "確定病例數")
  for (f in c("day", "week", "month")) {
    a <- twcovid:::.tw_flow(std, f, grp4, "cases")
    expect_equal(sum(a$cases), 15L, info = f)
    expect_true("cases" %in% names(a))
  }
})

test_that("balanced panel is a full rectangle and conserves totals", {
  std <- twcovid:::.tw_standardize(confirmed_raw(), "個案研判日", "確定病例數")
  for (f in c("day", "week", "month")) {
    a <- twcovid:::.tw_flow(std, f, grp4, "cases")
    b <- twcovid:::.tw_balance_panel(a, grp4, f, "cases")
    n_combo  <- nrow(unique(b[grp4]))
    n_period <- length(unique(b$period))
    expect_equal(nrow(b), n_combo * n_period, info = f)
    expect_equal(sum(b$cases), 15L, info = f)
    expect_false(any(is.na(b$cases)), info = f)
  }
})

test_that("start/end clip the period axis and the balanced range", {
  std <- twcovid:::.tw_standardize(confirmed_raw(), "個案研判日", "確定病例數")
  a <- twcovid:::.tw_flow(std, "month", "縣市", "cases",
                          start = "2022-01-01", end = "2022-01-31")
  b <- twcovid:::.tw_balance_panel(a, "縣市", "month", "cases",
                                   start = "2022-01-01", end = "2022-01-31")
  expect_true(all(format(b$period, "%Y-%m") == "2022-01"))
  expect_equal(sum(b$cases), 11L)  # Jan = 3+2+5+1, Feb (4) excluded
})

test_that("cumulative totals are running sums per cross-section", {
  std <- twcovid:::.tw_standardize(confirmed_raw(), "個案研判日", "確定病例數")
  a <- twcovid:::.tw_flow(std, "month", "縣市", "cases")
  b <- twcovid:::.tw_balance_panel(a, "縣市", "month", "cases")
  cum <- twcovid:::.tw_cumulate(b, "縣市", "cases")
  tpe <- cum[cum$縣市 == "臺北市", ]
  tpe <- tpe[order(tpe$period), ]
  expect_equal(tpe$cases, c(10L, 14L))          # Jan 3+2+5=10, +Feb 4 = 14
  # cumulative is non-decreasing within group
  expect_true(all(diff(tpe$cases) >= 0))
})

test_that("empty group_by yields a national series", {
  std <- twcovid:::.tw_standardize(confirmed_raw(), "個案研判日", "確定病例數")
  a <- twcovid:::.tw_flow(std, "day", character(0), "cases")
  expect_setequal(colnames(a), c("period", "cases"))
  expect_equal(sum(a$cases), 15L)
})

test_that("both-outcome merge aligns cases and deaths on a shared grid", {
  # two independent flow tables (confirmed by judgment, deaths by death date)
  conf <- dplyr::tibble(
    縣市 = c("A", "A", "B"),
    period = as.Date(c("2022-01-01", "2022-02-01", "2022-01-01")),
    cases = c(8L, 4L, 1L)
  )
  dea <- dplyr::tibble(
    縣市 = c("A", "B"),
    period = as.Date(c("2022-01-01", "2022-02-01")),
    deaths = c(2L, 1L)
  )
  by <- c("縣市", "period")
  merged <- dplyr::full_join(conf, dea, by = by)
  merged <- tidyr::replace_na(merged, list(cases = 0L, deaths = 0L))
  bal <- twcovid:::.tw_balance_panel(merged, "縣市", "month", c("cases", "deaths"))
  expect_equal(nrow(bal), 2L * 2L)                 # 2 counties x 2 months
  expect_equal(sum(bal$cases), 13L)
  expect_equal(sum(bal$deaths), 3L)
  expect_false(any(is.na(bal$cases)) || any(is.na(bal$deaths)))
})
