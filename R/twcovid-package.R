#' twcovid: Taiwan COVID-19 open data, made analysis-ready
#'
#' Download Taiwan CDC COVID-19 confirmed-case open data and tally it by
#' day / week / month, by onset date (發病日) or case-judgment date (個案研判日),
#' optionally zero-filled into a balanced panel. See [tw_covid()].
#'
#' @keywords internal
#' @importFrom rlang .data :=
#' @importFrom stats setNames
#' @importFrom utils download.file
"_PACKAGE"
