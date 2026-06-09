# ---------------------------------------------------------------------------
# Dataset registry
#
# Taiwan CDC publishes "地區年齡性別統計表" (region / age / sex tables) as DAILY
# files. We always pull the daily file and aggregate to week / month ourselves,
# so the day/week/month switch and the balanced panel stay under our control.
#
# Two outcomes are supported:
#   * confirmed (確定病例)  value column 確定病例數, by 發病日 / 個案研判日
#   * death     (死亡病例)  value column 死亡病例數, by 死亡日
#
# Each outcome x date_type maps to the daily source on data.gov.tw (gov_id) or
# the CDC open-data portal (cdc_id), used to resolve the *current* download URL
# via the open-data API, with hard-coded fallback URLs. Two case-definition
# "version" files exist per dataset:
#   * 19CoV = case definition before 2023/03/19
#   * 19CVS = current definition
# ---------------------------------------------------------------------------

.tw_registry <- list(
  confirmed = list(
    value_col  = "確定病例數",        # 確定病例數
    value_name = "cases",
    date_types = list(
      judgment = list(
        label    = "個案研判日",        # 個案研判日
        date_col = "個案研判日",
        gov_id   = 120711,
        urls = c(
          `19CoV` = "https://od.cdc.gov.tw/eic/Day_Confirmation_Age_County_Gender_19CoV.csv",
          `19CVS` = "https://od.cdc.gov.tw/eic/Day_Confirmation_Age_County_Gender_19CVS.csv"
        )
      ),
      onset = list(
        label    = "發病日",                    # 發病日
        date_col = "發病日",
        gov_id   = 151770,
        urls = c(
          `19CoV` = "https://od.cdc.gov.tw/eic/Age_County_Gender_day_19CoV.csv",
          `19CVS` = "https://od.cdc.gov.tw/eic/Age_County_Gender_day_19CVS.csv"
        )
      )
    )
  ),
  death = list(
    value_col  = "死亡病例數",        # 死亡病例數
    value_name = "deaths",
    date_types = list(
      death = list(
        label    = "死亡日",                    # 死亡日
        date_col = "死亡日",
        cdc_id   = "death-date-statistics-cases-19cov",
        urls = c(
          `19CoV` = "https://od.cdc.gov.tw/eic/open_data_death_date_statistics_19CoV_2.csv",
          `19CVS` = "https://od.cdc.gov.tw/eic/open_data_death_date_statistics_19CVS_2.csv"
        )
      )
    )
  )
)

# Which date_type each outcome supports, and the default.
.tw_outcome_date_types <- function(outcome) names(.tw_registry[[outcome]]$date_types)

# Categorical columns that may serve as panel (cross-section) dimensions.
.tw_group_cols <- c(
  "縣市",                      # county / city
  "鄉鎮",                      # township (mostly blank in source)
  "性別",                      # sex
  "是否為境外移入", # imported
  "年齡層"                 # age group
)

# ascii aliases (used when names = "en")
.tw_name_map <- c(
  "縣市" = "county",
  "鄉鎮" = "town",
  "性別" = "sex",
  "是否為境外移入" = "imported",
  "年齡層" = "age"
)

#' List the COVID-19 datasets twcovid knows about
#'
#' @return A data frame describing each available outcome x date_type source.
#' @export
tw_covid_datasets <- function() {
  rows <- list()
  for (oc in names(.tw_registry)) {
    o <- .tw_registry[[oc]]
    for (dt in names(o$date_types)) {
      e <- o$date_types[[dt]]
      rows[[length(rows) + 1]] <- data.frame(
        outcome    = oc,
        date_type  = dt,
        label      = e$label,
        date_col   = e$date_col,
        value_col  = o$value_col,
        source_id  = if (!is.null(e$gov_id)) as.character(e$gov_id) else e$cdc_id,
        url_19CoV  = e$urls[["19CoV"]],
        url_19CVS  = e$urls[["19CVS"]],
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}
