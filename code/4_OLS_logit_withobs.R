# OLS (continuous outcomes) and logistic regression (binary outcomes) comparison models.
# Intended for appendix: shows how standard regression compares to SuperLearner.
#
# Expects from master:
#   outcomes_spec  — list of lists with $name, $type ("cont"/"binary"), $group
#                    (only "all" group is expected here; mobility subsets not needed)
#   df_cleaned     — full cleaned data; this script handles grouping internally
#   countries      — character vector of country names
#   folds_per_rep, n_repeats
#   predictor vectors (famincedu, predictors017)
#   subset_group() — function defined in master
#   robustness_dir — output path (separate from main results)
#
# Note: predictors017 with OLS/logit will overfit badly.
# Warnings about perfect separation in logit are expected and can be ignored.

predictor_sets <- list(
  famincedu     = famincedu,
  predictors017 = predictors017
)

# --- Pre-compute one df per unique (outcome, group) combination ---
df_list <- list()
for (spec in outcomes_spec) {
  key <- paste(spec$name, spec$group, sep = "_")
  if (is.null(df_list[[key]])) {
    df_list[[key]] <- subset_group(df_cleaned, spec$group) |>
      drop_na(!!sym(spec$name))
  }
}

# --- Build task grid: outcome × pred_set × country × rep × fold ---
all_tasks <- list()

for (spec in outcomes_spec) {
  out    <- spec$name
  grp    <- spec$group
  og_key <- paste(out, grp, sep = "_")

  for (pred_set_name in names(predictor_sets)) {
    for (cname in countries) {
      df_sub <- df_list[[og_key]] |> filter(country == cname, child_obs >= 1)

      if (nrow(df_sub) < 10) {
        cat("Skipping", out, "/", grp, "/", pred_set_name, "/", cname,
            "— only", nrow(df_sub), "rows\n")
        next
      }

      for (rep in seq_len(n_repeats)) {
        set.seed(12345 + rep)
        folds <- createFolds(df_sub[[out]], k = folds_per_rep, list = TRUE)

        for (fold_idx in seq_along(folds)) {
          all_tasks <- c(all_tasks, list(list(
            outcome       = out,
            group         = grp,
            og_key        = og_key,
            family        = spec$type,
            pred_set_name = pred_set_name,
            cname         = cname,
            rep           = rep,
            fold          = fold_idx,
            test_idx      = folds[[fold_idx]],
            sample_size   = nrow(df_sub)
          )))
        }
      }
    }
  }
}

n_tasks <- length(all_tasks)
cat("\nOLS/Logit | Predictor sets:", paste(names(predictor_sets), collapse = ", "),
    "\nCountries:", paste(countries, collapse = ", "),
    "\nTotal parallel tasks:", n_tasks, "\n\n")

# --- Run all tasks in parallel ---
cl <- makeForkCluster(parallel::detectCores() - 1)
registerDoParallel(cl)

raw_results <- foreach(
  i         = seq_len(n_tasks),
  .packages = c("stats", "dplyr")
) %dopar% {
  task          <- all_tasks[[i]]
  out           <- task$outcome
  pred_set_name <- task$pred_set_name
  predictors    <- predictor_sets[[pred_set_name]]
  cname         <- task$cname
  rep           <- task$rep
  fold_idx      <- task$fold

  df_sub   <- df_list[[task$og_key]] |> filter(country == cname, child_obs >= 1)
  df_train <- df_sub[-task$test_idx, ]
  df_test  <- df_sub[ task$test_idx, ]

  y_train_mean <- mean(df_train[[out]])
  formula      <- as.formula(paste(out, "~", paste(predictors, collapse = " + ")))

  preds <- if (task$family == "binary") {
    model <- glm(formula, data = df_train, family = binomial)
    suppressWarnings(predict(model, newdata = df_test, type = "response"))
  } else {
    model <- lm(formula, data = df_train)
    predict(model, newdata = df_test)
  }

  ss_tot <- sum((df_test[[out]] - y_train_mean)^2)
  R2     <- 1 - sum((df_test[[out]] - preds)^2) / ss_tot

  list(
    outcome       = out,
    group         = task$group,
    family        = task$family,
    pred_set_name = pred_set_name,
    cname         = cname,
    rep           = rep,
    fold          = fold_idx,
    R2            = R2,
    sample_size   = task$sample_size
  )
}

stopCluster(cl)

# --- Aggregate and save ---
# Method label per outcome type: OLS for continuous, Logit for binary.
# Files go to robustness_dir, not output_dir.

fold_df <- map_dfr(raw_results, function(t) tibble(
  Country       = t$cname,
  Outcome       = t$outcome,
  Group         = t$group,
  Predictor_Set = t$pred_set_name,
  Min_Obs       = 1L,
  Rep           = t$rep,
  Fold          = t$fold,
  Sample_Size   = t$sample_size,
  R2            = t$R2
))

for (spec in outcomes_spec) {
  out       <- spec$name
  grp       <- spec$group
  out_label <- paste(out, grp, sep = "-")
  method    <- if (spec$type == "binary") "Logit" else "OLS"

  for (ps_name in names(predictor_sets)) {
    sub_df <- fold_df |> filter(Outcome == out, Group == grp, Predictor_Set == ps_name)
    if (nrow(sub_df) == 0) next

    rep_results <- sub_df |>
      group_by(Country, Outcome, Group, Predictor_Set, Min_Obs, Rep, Sample_Size) |>
      summarise(R2 = mean(R2), .groups = "drop")

    results <- rep_results |>
      group_by(Country, Outcome, Group, Predictor_Set, Min_Obs, Sample_Size) |>
      summarise(R2 = round(mean(R2), 3), .groups = "drop")

    fname_suffix <- paste0("_", out_label, "_", ps_name)
    write_csv(results,     file.path(robustness_dir, paste0("table",       fname_suffix, "_", method, ".csv")))
    write_csv(rep_results, file.path(robustness_dir, paste0("rep_results", fname_suffix, "_", method, ".csv")))

    cat("Saved:", out_label, "/", ps_name, "/", method, "\n")
    print(results)
  }
}
