# ---------------------------------------------------------------------------
# Resolving download URLs + downloading / caching the raw daily CSV files
# ---------------------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x)) y else x

# Tag a vector of URLs with their case-definition version code.
.tw_tag_versions <- function(urls) {
  nm <- ifelse(grepl("19CVS", urls), "19CVS",
        ifelse(grepl("19CoV", urls), "19CoV", NA_character_))
  urls <- urls[!is.na(nm)]
  stats::setNames(urls, nm[!is.na(nm)])
}

# Resolve current CSV URLs from the data.gov.tw open-data API (by numeric id).
.tw_govtw_urls <- function(gov_id) {
  tryCatch({
    api <- sprintf("https://data.gov.tw/api/v2/rest/dataset/%s", gov_id)
    js  <- jsonlite::fromJSON(api, simplifyVector = FALSE)
    dist <- js$result$distribution
    urls <- vapply(dist, function(d) {
      if (identical(d$resourceFormat, "CSV")) d$resourceDownloadUrl else NA_character_
    }, character(1))
    .tw_tag_versions(urls[!is.na(urls)])
  }, error = function(e) character(0))
}

# Resolve current CSV URLs from the CDC open-data CKAN portal (by slug id).
.tw_cdc_urls <- function(cdc_id) {
  tryCatch({
    api <- sprintf("https://data.cdc.gov.tw/api/3/action/package_show?id=%s", cdc_id)
    js  <- jsonlite::fromJSON(api, simplifyVector = FALSE)
    res <- js$result$resources
    urls <- vapply(res, function(r) {
      if (toupper(r$format %||% "") == "CSV") r$url else NA_character_
    }, character(1))
    .tw_tag_versions(urls[!is.na(urls)])
  }, error = function(e) character(0))
}

# Resolve the list of (version -> url) to download for one outcome/date_type.
.tw_resolve_urls <- function(entry, version, use_api = TRUE) {
  urls <- entry$urls
  if (use_api) {
    api_urls <- if (!is.null(entry$gov_id)) {
      .tw_govtw_urls(entry$gov_id)
    } else if (!is.null(entry$cdc_id)) {
      .tw_cdc_urls(entry$cdc_id)
    } else {
      character(0)
    }
    for (v in names(api_urls)) urls[[v]] <- api_urls[[v]]
  }
  if (identical(version, "both")) {
    urls
  } else {
    keep <- urls[version]
    keep[!is.na(keep)]
  }
}

.tw_cache_dir <- function(cache_dir = NULL) {
  d <- cache_dir %||% file.path(tempdir(), "twcovid-cache")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# Browser-like User-Agent (some od.cdc.gov.tw paths reject default agents).
.tw_user_agent <- function() {
  paste0("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ",
         "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36")
}

# Try download.file with a couple of methods; return the error message (or NULL
# on success). Downloads to a temp file and renames on success so a partial /
# failed download never poisons the cache.
.tw_try_download <- function(url, dest, quiet, timeout = 600L) {
  old <- options(timeout = max(timeout, getOption("timeout", 60L)),
                 HTTPUserAgent = .tw_user_agent())
  on.exit(options(old), add = TRUE)

  tmp <- paste0(dest, ".part")
  last_err <- NULL
  for (m in c("libcurl", "curl", "auto")) {
    ok <- tryCatch({
      suppressWarnings(
        utils::download.file(url, tmp, mode = "wb", quiet = quiet, method = m)
      )
      file.exists(tmp) && file.info(tmp)$size > 0
    }, error = function(e) { last_err <<- conditionMessage(e); FALSE })
    if (isTRUE(ok)) {
      file.rename(tmp, dest)
      return(NULL)
    }
    if (file.exists(tmp)) unlink(tmp)
  }
  last_err %||% "unknown download error"
}

# Download (or read from cache) one CSV. The cache key includes the current
# date so the daily-refreshed source is re-fetched at most once per day.
.tw_download_csv <- function(url, cache = TRUE, cache_dir = NULL, quiet = TRUE) {
  dir <- .tw_cache_dir(cache_dir)
  key <- paste0(
    gsub("[^A-Za-z0-9]+", "_", basename(url)), "_",
    format(Sys.Date(), "%Y%m%d"), ".csv"
  )
  path <- file.path(dir, key)

  if (!(cache && file.exists(path) && file.info(path)$size > 0)) {
    err <- .tw_try_download(url, path, quiet = quiet)
    if (!is.null(err)) {
      stop("Failed to download ", url, "\n  reason: ", err,
           "\n  (Check internet / proxy access to od.cdc.gov.tw. ",
           "Behind a proxy? set Sys.setenv(https_proxy=...).)",
           call. = FALSE)
    }
  }

  readr::read_csv(
    path,
    locale = readr::locale(encoding = "UTF-8"),
    col_types = readr::cols(.default = readr::col_character()),
    progress = FALSE,
    show_col_types = FALSE
  )
}

#' Clear the twcovid download cache
#'
#' @param cache_dir Cache directory (defaults to the package temp cache).
#' @return Invisibly, the number of files removed.
#' @export
tw_covid_clear_cache <- function(cache_dir = NULL) {
  dir <- .tw_cache_dir(cache_dir)
  files <- list.files(dir, full.names = TRUE)
  unlink(files)
  invisible(length(files))
}
