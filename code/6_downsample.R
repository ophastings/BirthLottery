# Downsampling robustness: tests whether USA's higher predictability is just a sample-size artifact.
# Subsamples USA to match smaller countries' n, then compares CV R² to true holdout R².
# Full USA predictors017 results already exist in output/ from the main analysis.
#
# Expects from master:
#   outcomes_spec  — full-sample ("all" group) outcomes only
#   df_cleaned     — full cleaned data
#   folds_per_rep, n_repeats, sl_cv_V
#   predictors017, famincedu (only predictors017 used here)
#   subset_group(), robustness_dir

SL.ranger.fast  <- function(...) SL.ranger(...,  num.trees = 200)
SL.xgboost.fast <- function(...) SL.xgboost(..., nrounds = 100, max_depth = 4)

# Sample sizes chosen to match Germany (2765), UK (1843), and smallest mobility subgroup (418)
sample_sizes <- c(2765, 1843, 418)
predictors   <- predictors017

# --- Pre-compute USA-only df per outcome ---
usa_df_list <- map(outcomes_spec, function(spec) {
  df_cleaned |>
    drop_na(!!sym(spec$name)) |>
    filter(country == "USA", child_obs >= 1)
}) |> set_names(map_chr(outcomes_spec, ~ .x$name))

# --- Pre-compute all train/holdout splits and CV fold assignments ---
# Done outside the parallel loop so seeds are deterministic.

split_tasks <- list()

for (spec in outcomes_spec) {
  out   <- spec$name
  df_us <- usa_df_list[[out]]
  n_usa <- nrow(df_us)

  for (n_sample in sample_sizes) {
    if (n_sample >= n_usa) {
      cat("Skipping", out, "/ n =", n_sample, "— not smaller than full USA n =", n_usa, "\n")
      next
    }

    for (rep in seq_len(n_repeats)) {
      set.seed(1000 + n_sample + rep)
      train_idx <- sample(seq_len(n_usa), size = n_sample)

      # CV folds are created within the training set
      df_train <- df_us[train_idx, ]
      set.seed(12345 + rep)
      folds <- createFolds(df_train[[out]], k = folds_per_rep, list = TRUE)

      split_tasks <- c(split_tasks, list(list(
        outcome    = out,
        family     = spec$type,
        n_sample   = n_sample,
        rep        = rep,
        train_idx  = train_idx,
        folds      = folds,
        n_usa      = n_usa
      )))
    }
  }
}

n_tasks <- length(split_tasks)
cat("\nDownsampling | Outcomes:", paste(map_chr(outcomes_spec, ~ .x$name), collapse = ", "),
    "\nSample sizes:", paste(sample_sizes, collapse = ", "),
    "\nReps:", n_repeats, "| Total parallel tasks:", n_tasks, "\n\n")

# --- Run all tasks in parallel ---
# Each task: 5-fold CV within the subsample + one final holdout fit.
# Sequential within the task to avoid nested parallelism.

cl <- makeForkCluster(parallel::detectCores() - 1)
registerDoParallel(cl)

raw_results <- foreach(
  i         = seq_len(n_tasks),
  .packages = c("SuperLearner", "dplyr", "purrr")
) %dopar% {
  task      <- split_tasks[[i]]
  out       <- task$outcome
  sl_family <- if (task$family == "binary") binomial() else gaussian()

  df_us    <- usa_df_list[[out]]
  df_train <- df_us[ task$train_idx, ]
  df_hold  <- df_us[-task$train_idx, ]

  y_train_mean <- mean(df_train[[out]])

  # 5-fold CV within the training subsample → CV R²
  fold_r2s <- map_dbl(seq_along(task$folds), function(f) {
    set.seed(12345 + task$rep * 100 + f)
    cv_train <- df_train[-task$folds[[f]], ]
    cv_test  <- df_train[ task$folds[[f]], ]

    sl_fit <- SuperLearner(
      Y          = cv_train[[out]],
      X          = cv_train[, predictors, drop = FALSE],
      SL.library = c("SL.glmnet", "SL.ranger.fast", "SL.xgboost.fast"),
      family     = sl_family,
      cvControl  = list(V = sl_cv_V)
    )
    pred   <- predict(sl_fit, newdata = cv_test[, predictors, drop = FALSE])$pred
    ss_tot <- sum((cv_test[[out]] - y_train_mean)^2)
    1 - sum((cv_test[[out]] - pred)^2) / ss_tot
  })

  R2_CV <- mean(fold_r2s)

  # Final fit on full training subsample → true holdout R²
  set.seed(12345 + task$rep * 100)
  sl_final <- SuperLearner(
    Y          = df_train[[out]],
    X          = df_train[, predictors, drop = FALSE],
    SL.library = c("SL.glmnet", "SL.ranger.fast", "SL.xgboost.fast"),
    family     = sl_family,
    cvControl  = list(V = sl_cv_V)
  )
  pred_hold   <- predict(sl_final, newdata = df_hold[, predictors, drop = FALSE])$pred
  ss_tot_hold <- sum((df_hold[[out]] - y_train_mean)^2)
  R2_Holdout  <- 1 - sum((df_hold[[out]] - pred_hold)^2) / ss_tot_hold

  cat("Done:", out, "| n =", task$n_sample, "| rep", task$rep,
      "| CV R²:", round(R2_CV, 3), "| Holdout R²:", round(R2_Holdout, 3), "\n")

  list(
    Outcome    = out,
    Sample_Size = task$n_sample,
    Rep        = task$rep,
    R2_CV      = R2_CV,
    R2_Holdout = R2_Holdout
  )
}

stopCluster(cl)

# --- Aggregate and save ---

results_df <- map_dfr(raw_results, ~ tibble(
  Outcome     = .x$Outcome,
  Sample_Size = .x$Sample_Size,
  Rep         = .x$Rep,
  R2_CV       = .x$R2_CV,
  R2_Holdout  = .x$R2_Holdout
))

# Rep-level detail (useful for checking variance across draws)
write_csv(results_df, file.path(robustness_dir, "downsample_r2_byrep.csv"))

# Summary: mean over reps — this is what the figure script needs
summary_df <- results_df |>
  group_by(Outcome, Sample_Size) |>
  summarise(
    R2_CV_Mean      = mean(R2_CV),
    R2_Holdout_Mean = mean(R2_Holdout),
    .groups = "drop"
  )

write_csv(summary_df, file.path(robustness_dir, "downsample_r2_summary.csv"))

cat("\nDownsampling complete.\n")
print(summary_df)
