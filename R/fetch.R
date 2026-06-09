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
    ok <- tryCatch({
      utils::download.file(url, path, mode = "wb", quiet = quiet)
      TRUE
    }, error = function(e) FALSE)
    if (!ok || !file.exists(path) || file.info(path)$size == 0) {
      stop("Failed to download: ", url,
           "\nCheck your internet connection / access to od.cdc.gov.tw.",
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
