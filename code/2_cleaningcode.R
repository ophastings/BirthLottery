library(fastDummies)

# Basic demographic and childhood observation covariates
covar_basic <- c(
  "female", "first_age_obs", "living_child_head",
  "age_of_mom_at_birth", "age_of_dad_at_birth",
  "obsage_05", "obsage_610", "obsage_1117", "age_max"
)

# Childhood circumstance variables (full childhood, ages 0-10, ages 11-17)
vars_017 <- c(
  "share_child_nomale", "share_child_nofemale",
  "employ_mom", "employ_dad",
  "child_under_uniqueadult", "avg_num_child"
)

vars_010 <- c(
  "d_share_child_nofemale_010", "d_share_child_nomale_010",
  "d_employ_dad_010", "d_employ_mom_010",
  "d_avg_num_child_010", "d_child_under_uniqueadult_010"
)

vars_1117 <- c(
  "d_share_child_nofemale_1117", "d_share_child_nomale_1117",
  "d_employ_dad_1117", "d_employ_mom_1117",
  "d_avg_num_child_117", "d_child_under_uniqueadult_117"
)

# Childhood income decile dummies (full childhood, ages 0-10, ages 11-17)
childinc <- paste0("d_ch_", 1:10)

childinc_010  <- paste0("d_ch_010_",  1:10)
childinc_1117 <- paste0("d_ch_1117_", 1:10)

# Industry and education variables
indus <- c("industry_mom", "industry_dad")

parent_attain_categories <- c("edu_attain_mom", "edu_attain_dad")
parent_attain_years      <- c("edu_years_mom",  "edu_years_dad")

# USA-only PSID variables
usa <- c(
  "z_wealth_decile", "z_foodinsecure", "z_disability",
  "z_homeowner", "z_health_sr", "z_health_asthhbp", "z_incarc",
  "rblack", "rwhite",
  parent_attain_years
)

years <- c("year_age25")

# --- Missing indicator creation ---
# For each variable: create a miss_* indicator (1 = missing) and recode NA to -1

all_vars <- c(covar_basic, indus, parent_attain_categories)

for (x in all_vars) {
  df[[paste0("miss_", x)]] <- as.integer(is.na(df[[x]]))
  df[[x]][is.na(df[[x]])] <- -1
}

for (x in vars_017) {
  df[[paste0("miss017_", x)]] <- as.integer(is.na(df[[x]]))
  df[[x]][is.na(df[[x]])] <- -1
}

for (x in vars_010) {
  df[[paste0("miss010_", x)]] <- as.integer(is.na(df[[x]]))
  df[[x]][is.na(df[[x]])] <- -1
}

for (x in vars_1117) {
  df[[paste0("miss1117_", x)]] <- as.integer(is.na(df[[x]]))
  df[[x]][is.na(df[[x]])] <- -1
}

for (x in usa) {
  df[[paste0("missusa_", x)]] <- as.integer(is.na(df[[x]]))
  df[[x]][is.na(df[[x]])] <- -1
}

# --- Dummy coding ---

df[indus] <- lapply(df[indus], as.factor)

df <- dummy_cols(
  df,
  select_columns       = c(indus, years, parent_attain_categories),
  remove_selected_columns = TRUE
)

# Drop the reference/missing category dummies (columns ending in -1)
df <- df |> select(-ends_with("-1"))

# --- Collect variable name lists for predictor set construction ---

indus_cols_names  <- names(df)[grepl("^(industry_mom_|industry_dad_)", names(df))]
years_cols_names  <- names(df)[grepl("^(year_age25_)",                 names(df))]
parent_cols_names <- names(df)[grepl("^(edu_attain_mom_|edu_attain_dad_)", names(df))]

miss_vars     <- names(df)[grepl("^miss_",     names(df))]
missusa_vars  <- names(df)[grepl("^missusa_",  names(df))]
miss017_vars  <- names(df)[grepl("^miss017_",  names(df))]
miss010_vars  <- names(df)[grepl("^miss010_",  names(df))]
miss1117_vars <- names(df)[grepl("^miss1117_", names(df))]

# --- Income rank indicators ---

# Childhood income decile dummies (rank 1-10)
for (q in 1:10) {
  df[[paste0("d_ch_", q)]] <- with(df, rank_ch_hh_net_inc_eq >= q & rank_ch_hh_net_inc_eq <= (q + 0.999))
}

# Adult income decile dummies
for (q in 1:10) {
  df[[paste0("d_ad_", q)]] <- with(df, rank_ad_hh_net_inc_eq >= q & rank_ad_hh_net_inc_eq <= (q + 0.999))
}

# Adult log income
df$log_ad_inc <- log(df$m_hh_net_inc_eq_ad)

# Binary adult outcomes
df$top10   <- with(df, ifelse(d_ad_10 == TRUE & !is.na(rank_ad_hh_net_inc_eq), 1, 0))
df$top20   <- with(df, ifelse((d_ad_10 | d_ad_9) & !is.na(rank_ad_hh_net_inc_eq), 1, 0))
df$top50   <- with(df, ifelse(rank_ad_hh_net_inc_eq >= 5 & !is.na(rank_ad_hh_net_inc_eq), 1, 0))
df$bottom20 <- with(df, ifelse(rank_ad_hh_net_inc_eq <= 2 & !is.na(rank_ad_hh_net_inc_eq), 1, 0))
df$bottom10 <- with(df, ifelse(d_ad_1 == TRUE & !is.na(rank_ad_hh_net_inc_eq), 1, 0))
df$bottom50 <- with(df, ifelse(rank_ad_hh_net_inc_eq < 5 & !is.na(rank_ad_hh_net_inc_eq), 1, 0))

# Continuous childhood and adult income decile (1-10 integer)
df <- df |>
  mutate(
    chcont = case_when(
      d_ch_1  ~ 1,  d_ch_2  ~ 2,  d_ch_3  ~ 3,  d_ch_4  ~ 4,
      d_ch_5  ~ 5,  d_ch_6  ~ 6,  d_ch_7  ~ 7,  d_ch_8  ~ 8,
      d_ch_9  ~ 9,  d_ch_10 ~ 10, TRUE ~ NA_real_
    ),
    adcont = case_when(
      d_ad_1  ~ 1,  d_ad_2  ~ 2,  d_ad_3  ~ 3,  d_ad_4  ~ 4,
      d_ad_5  ~ 5,  d_ad_6  ~ 6,  d_ad_7  ~ 7,  d_ad_8  ~ 8,
      d_ad_9  ~ 9,  d_ad_10 ~ 10, TRUE ~ NA_real_
    )
  )
