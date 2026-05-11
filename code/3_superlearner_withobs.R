# Expects from master:
#   outcomes_spec  — list of lists, each with:
#                      $name  : outcome variable name
#                      $type  : "cont" or "binary"
#                      $group : "all", "childbottom20", or "childtop20"
#   df_cleaned     — full cleaned data (not pre-subsetted; this script handles grouping)
#   countries      — character vector of country names
#   folds_per_rep, n_repeats, sl_cv_V
#   predictor vectors (childinc, famincedu, predictors010, predictors017)
#   subset_group() — function defined in master
#   output_dir
#   predictor_sets — optional override; if not defined, defaults to the standard four sets

# --- Faster base learner wrappers ---
SL.ranger.fast  <- function(...) SL.ranger(...,  num.trees = 200)
SL.xgboost.fast <- function(...) SL.xgboost(..., nrounds = 100, max_depth = 4)

# Use predictor_sets/min_obs/fname_tag from the calling environment if already defined.
if (!exists("predictor_sets")) {
  predictor_sets <- list(
    # childinc      = childinc,
    famincedu     = famincedu,
    predictors010 = predictors010,
    predictors017 = predictors017
  )
}
if (!exists("min_obs"))  min_obs  <- 1L
if (!exists("fname_tag")) fname_tag <- ""

# --- Pre-compute one df per unique (outcome, group) combination ---
# Key format: "outcome_group" e.g. "poverty_all", "top50_childbottom20"

df_list <- list()
for (spec in outcomes_spec) {
  key <- paste(spec$name, spec$group, sep = "_")
  if (is.null(df_list[[key]])) {
    df_list[[key]] <- subset_group(df_cleaned, spec$group) |>
      drop_na(!!sym(spec$name))
  }
}

# --- Build the full task grid ---
# One task = one SuperLearner fit: outcome × group × pred_set × country × rep × fold

all_tasks <- list()

for (spec in outcomes_spec) {
  out     <- spec$name
  grp     <- spec$group
  og_key  <- paste(out, grp, sep = "_")

  for (pred_set_name in names(predictor_sets)) {
    for (cname in countries) {
      df_sub <- df_list[[og_key]] |> filter(country == cname, child_obs >= min_obs)

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
cat("\nOutcomes/groups:\n")
walk(outcomes_spec, ~ cat(" ", .x$name, "/", .x$group, "\n"))
cat("Predictor sets:", paste(names(predictor_sets), collapse = ", "),
    "\nCountries:", paste(countries, collapse = ", "),
    "\nTotal parallel tasks:", n_tasks, "\n\n")

# Progress log — file writes bypass R's output buffer so lines appear in real time.
# Follow with:  tail -f <path printed below>
.log_file <- file.path(output_dir, "sl_progress.log")
writeLines(character(0), .log_file)  # clear from previous run
cat("Progress log:", .log_file, "\n")

# --- Run all tasks in parallel ---
# Workers share df_list, predictor_sets, and df_cleaned via fork (no copying).

cl <- makeForkCluster(parallel::detectCores() - 1)
registerDoParallel(cl)

raw_results <- foreach(
  i         = seq_len(n_tasks),
  .packages = c("SuperLearner", "dplyr")
) %dopar% {
  task          <- all_tasks[[i]]
  out           <- task$outcome
  pred_set_name <- task$pred_set_name
  predictors    <- predictor_sets[[pred_set_name]]
  cname         <- task$cname
  rep           <- task$rep
  fold_idx      <- task$fold
  sl_family     <- if (task$family == "binary") binomial() else gaussian()

  df_sub   <- df_list[[task$og_key]] |> filter(country == cname, child_obs >= min_obs)
  df_train <- df_sub[-task$test_idx, ]
  df_test  <- df_sub[ task$test_idx, ]

  set.seed(12345 + rep * 100 + fold_idx)

  y_train_mean <- mean(df_train[[out]])

  sl_fit <- SuperLearner(
    Y          = df_train[[out]],
    X          = df_train[, predictors, drop = FALSE],
    SL.library = c("SL.glmnet", "SL.ranger.fast", "SL.xgboost.fast"),
    family     = sl_family,
    cvControl  = list(V = sl_cv_V)
  )

  pred_sl <- predict(sl_fit, newdata = df_test[, predictors, drop = FALSE])$pred
  ss_tot  <- sum((df_test[[out]] - y_train_mean)^2)
  R2_sl   <- 1 - sum((df_test[[out]] - pred_sl)^2) / ss_tot

  cat(sprintf("[%d/%d] %s / %s / %s / %s  rep %d fold %d  R2=%.3f\n",
              i, n_tasks, cname, out, task$group, pred_set_name,
              rep, fold_idx, R2_sl),
      file = .log_file, append = TRUE)

  list(
    outcome       = out,
    group         = task$group,
    pred_set_name = pred_set_name,
    cname         = cname,
    rep           = rep,
    fold          = fold_idx,
    R2            = R2_sl,
    sample_size   = task$sample_size,
    coef          = data.frame(
      Algo          = names(sl_fit$coef),
      Weight        = as.vector(sl_fit$coef),
      Country       = cname,
      Outcome       = out,
      Group         = task$group,
      Rep           = rep,
      Fold          = fold_idx,
      Predictor_Set = pred_set_name,
      Min_Obs       = min_obs,
      stringsAsFactors = FALSE
    )
  )
}

stopCluster(cl)

# --- Aggregate and save ---
# Output filename: table_<outcome>-<group>_<pred_set>_SuperLearner.csv
# e.g. table_poverty-all_predictors017_SuperLearner.csv
#      table_top50-childbottom20_famincedu_SuperLearner.csv

fold_df <- map_dfr(raw_results, function(t) tibble(
  Country       = t$cname,
  Outcome       = t$outcome,
  Group         = t$group,
  Predictor_Set = t$pred_set_name,
  Min_Obs       = min_obs,
  Rep           = t$rep,
  Fold          = t$fold,
  Sample_Size   = t$sample_size,
  R2            = t$R2
))

sl_weights_all <- map_dfr(raw_results, ~ .x$coef)

for (spec in outcomes_spec) {
  out       <- spec$name
  grp       <- spec$group
  out_label <- paste(out, grp, sep = "-")

  for (ps_name in names(predictor_sets)) {
    sub_df <- fold_df |> filter(Outcome == out, Group == grp, Predictor_Set == ps_name)
    if (nrow(sub_df) == 0) next

    rep_results <- sub_df |>
      group_by(Country, Outcome, Group, Predictor_Set, Min_Obs, Rep, Sample_Size) |>
      summarise(SuperLearner = mean(R2), .groups = "drop")

    results <- rep_results |>
      group_by(Country, Outcome, Group, Predictor_Set, Min_Obs, Sample_Size) |>
      summarise(SuperLearner = round(mean(SuperLearner), 3), .groups = "drop")

    sl_weights <- sl_weights_all |>
      filter(Outcome == out, Group == grp, Predictor_Set == ps_name)

    fname_suffix <- paste0("_", out_label, "_", ps_name, fname_tag)
    write_csv(results,     file.path(output_dir, paste0("table",       fname_suffix, "_SuperLearner.csv")))
    write_csv(rep_results, file.path(output_dir, paste0("rep_results", fname_suffix, "_SuperLearner.csv")))
    write_csv(sl_weights,  file.path(output_dir, paste0("sl_weights",  fname_suffix, ".csv")))

    cat("Saved:", out_label, "/", ps_name, "\n")
    print(results)
  }
}
