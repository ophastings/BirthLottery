# PSID robustness analysis: enriched USA-only predictors vs the standard model.
# Reuses 3_superlearner_withobs.R — the only differences are the predictor sets,
# the country restriction, reduced repeats (USA is large), and output going to robustness/.
#
# Compares:
#   predictors017 — the standard CNEF harmonized model (same as main analysis)
#   predictorsusa — enriched PSID model adding race, wealth, incarceration, health, etc.

# --- Save state that will be temporarily overridden ---
.psid_saved <- list(
  countries  = countries,
  output_dir = output_dir,
  n_repeats  = n_repeats
)

# --- PSID-specific configuration ---
countries  <- c("USA")
output_dir <- robustness_dir
n_repeats  <- 1   # USA sample is large; one repeat is sufficient for this comparison
fname_tag  <- "_psid"

predictor_sets <- list(
  predictorsusa = predictorsusa  # enriched model — adds race, wealth, incarceration, etc.
)
# Note: predictors017 results for USA already exist in output/ from the main analysis
# and can be used directly as the comparison baseline in the appendix figure.

outcomes_spec <- list(
  list(name = "poverty",   type = "cont",   group = "all"),
  list(name = "education", type = "cont",   group = "all"),
  list(name = "adcont",    type = "cont",   group = "all"),
  list(name = "top10",     type = "binary", group = "all")
)

# --- Run SuperLearner via the shared script ---
source(file.path(scripts, "3_superlearner_withobs.R"))

# --- Restore state ---
countries  <- .psid_saved$countries
output_dir <- .psid_saved$output_dir
n_repeats  <- .psid_saved$n_repeats
rm(predictor_sets, fname_tag, .psid_saved)
