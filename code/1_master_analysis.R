library(tidyverse)
library(caret)
library(glmnet)
library(haven)
library(doParallel)
library(foreach)
library(SuperLearner)
library(here)

# Paths — resolved relative to the project root via here()
scripts        <- here("code")
output_dir     <- here("output", "results")
robustness_dir <- here("output", "results", "robustness")
dir.create(output_dir,     showWarnings = FALSE, recursive = TRUE)
dir.create(robustness_dir, showWarnings = FALSE, recursive = TRUE)

# Load data
df <- read_dta(here("data", "data_ready-v4.dta")) |>
  rename(
    poverty       = poverty_2426,
    education     = years_of_edu,
    child_obs     = obsage_017_c,
    edu_years_mom = edu_attain_mom_years,
    edu_years_dad = edu_attain_dad_years
  )

# Clean variables
source(file.path(scripts, "2_cleaningcode.R"))

df <- df |> drop_na(chcont)

# Snapshot of cleaned data
df_cleaned <- df

# --- Predictor sets ---

predictors017 <- c(childinc, covar_basic, vars_017, miss_vars, miss017_vars, parent_cols_names, indus_cols_names, years_cols_names)
predictors010 <- c(childinc_010, covar_basic, vars_010, miss_vars, miss010_vars, parent_cols_names, indus_cols_names, years_cols_names)
predictorsusa <- c(predictors017, usa, missusa_vars)

parentedu <- c(parent_cols_names, "miss_edu_attain_mom", "miss_edu_attain_dad")
famincedu <- c(childinc, parentedu)

# --- Countries ---
# countries <- c("GERMANY", "KOREA")  # testing: two mid-size countries
# countries <- c("AUSTRALIA")         # testing: one small country
countries <- c("USA", "GERMANY", "AUSTRALIA", "KOREA", "UK")

# --- Mobility subsetting ---
subset_group <- function(df, group) {
  if (group == "all")          return(df)
  if (group == "childbottom20") return(subset(df, d_ch_1 == 1 | d_ch_2 == 1))
  if (group == "childtop20")    return(subset(df, d_ch_9 == 1 | d_ch_10 == 1))
  stop("Invalid group: ", group)
}

# --- CV parameters ---
folds_per_rep <- 5
n_repeats     <- 3
sl_cv_V       <- 3   # SuperLearner internal CV folds

# ============================================================
# FULL ANALYSIS
# ============================================================


# Each entry: name = outcome variable, type = "cont"/"binary", group = sample subset
outcomes_spec <- list(
  # Full sample
  list(name = "poverty",   type = "cont",   group = "all"),
  list(name = "education", type = "cont",   group = "all"),
  list(name = "adcont",    type = "cont",   group = "all"),
  list(name = "top10",     type = "binary", group = "all"),
  # Bottom 20% mobility
  list(name = "poverty",   type = "cont",   group = "childbottom20"),
  list(name = "top50",     type = "binary", group = "childbottom20"),
  # Top 20% mobility
  list(name = "bottom50",  type = "binary", group = "childtop20"),
  list(name = "top20",     type = "binary", group = "childtop20")
)

# t_start <- proc.time()
# source(file.path(scripts, "3_superlearner_withobs.R"))
# cat("\nElapsed:", round((proc.time() - t_start)["elapsed"], 1), "seconds\n")


source(file.path(scripts, "3_superlearner_withobs.R"))

# ============================================================
# ROBUSTNESS — OLS / logit vs SuperLearner (appendix)
# ============================================================

# Full-sample outcomes only; no mobility subsets needed for this comparison.
# Results go to robustness/ so they stay separate from the main output.

outcomes_spec <- list(
  list(name = "poverty",   type = "cont",   group = "all"),
  list(name = "education", type = "cont",   group = "all"),
  list(name = "adcont",    type = "cont",   group = "all"),
  list(name = "top10",     type = "binary", group = "all")
)

source(file.path(scripts, "4_OLS_logit_withobs.R"))

# ============================================================
# ROBUSTNESS — PSID enriched predictors (appendix)
# ============================================================

# Runs SuperLearner for USA only, comparing predictors017 to the enriched PSID
# model (adds race, wealth, incarceration, health, etc.). Reuses 3_superlearner_withobs.R.
# Results go to robustness/. outcomes_spec is defined inside 5_psid.R.

source(file.path(scripts, "5_psid.R"))

# ============================================================
# ROBUSTNESS — Downsampling (appendix)
# ============================================================

# Subsamples USA to match smaller countries' n (2765, 1843, 418) to test whether
# USA's higher predictability is a sample-size artifact. Reports both CV R² and
# true holdout R² (on the excluded rows). Full USA result comes from output/.

outcomes_spec <- list(
  list(name = "poverty",   type = "cont",   group = "all"),
  list(name = "education", type = "cont",   group = "all"),
  list(name = "adcont",    type = "cont",   group = "all"),
  list(name = "top10",     type = "binary", group = "all")
)

source(file.path(scripts, "6_downsample.R"))

# ============================================================
# ROBUSTNESS — Min observations >= 3 (appendix)
# ============================================================

# Reruns SuperLearner for full-sample outcomes requiring at least 3 childhood
# observations instead of 1. Tests sensitivity to observation-count threshold.

outcomes_spec <- list(
  list(name = "poverty",   type = "cont",   group = "all"),
  list(name = "education", type = "cont",   group = "all"),
  list(name = "adcont",    type = "cont",   group = "all"),
  list(name = "top10",     type = "binary", group = "all")
)

.minobs_saved_dir <- output_dir
output_dir <- robustness_dir
min_obs    <- 3L
fname_tag  <- "_minobs3"

source(file.path(scripts, "3_superlearner_withobs.R"))

output_dir <- .minobs_saved_dir
min_obs    <- 1L
fname_tag  <- ""
rm(.minobs_saved_dir)

