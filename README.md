# Replication Code: Predicting the Birth Lottery

This repository contains the replication code and results for:

> Hastings, P. *Rags or Riches? Predicting Life Outcomes from the Birth Lottery Across Five High-Income Countries.*

---

## Overview

This project uses SuperLearner ensemble machine learning — combining LASSO, random forests, and gradient boosting with repeated cross-validation — to predict adult life outcomes from childhood circumstances in five high-income countries: the United States, Germany, Australia, South Korea, and the United Kingdom.

**Outcomes predicted:** poverty in adulthood, top 10% income, years of education, and adult income decile rank. Mobility analyses predict upward and downward mobility for children born into the bottom and top 20% of the income distribution.

---

## Data access

The main data files are **not included** in this folder. They come from the [Cross-National Equivalent File (CNEF)](https://cnef.ehe.osu.edu/), a harmonized set of national panel surveys. Access requires registration and approval directly from CNEF.

Once you have access, you will need one file:

| File | Description |
|---|---|
| `data_ready-v4.dta` | Main analysis dataset — five countries, childhood predictors ages 0–17 |

Place it in the `data/` folder before running any analysis scripts.

The file `data/otherdata_Sept.csv` is included — it contains country-level contextual indicators (Gini coefficients, intergenerational income elasticity, etc.) used in Figure 6.

---

## Folder structure

```
BirthLottery/
├── BirthLottery.Rproj     # Open this in RStudio first
├── code/                  # All R scripts
├── data/                  # Data files (add CNEF .dta files here)
└── output/
    ├── results/           # All output CSVs (main analysis + robustness)
    │   └── robustness/    # Robustness check CSVs
    └── figures/           # All paper figures (PDFs)
```

Pre-computed results CSVs are included in `output/results/` so that figures can be reproduced without re-running the full analysis (which is computationally intensive).

---

## Getting started

**Open `BirthLottery.Rproj` in RStudio.** This sets the working directory correctly — all scripts use the `here` package to build paths relative to the project root, so they will work regardless of where the folder is stored on your machine.

### Required R packages

Install any missing packages before running:

```r
install.packages(c(
  "tidyverse", "haven", "caret", "glmnet",
  "SuperLearner", "ranger", "xgboost",
  "doParallel", "foreach", "here"
))

# Two figure packages not on CRAN:
devtools::install_github("coolbutuseless/ggpattern")
remotes::install_github("jimjam-slam/ggflags")
```

### Reproducing the figures

If you only want to reproduce the paper figures from the pre-computed results:

1. Open `BirthLottery.Rproj`
2. Run `code/8_figures.R`

Figures are saved as PDFs to `output/figures/`.

### Re-running the full analysis

To re-run the analysis from scratch (requires the CNEF data files):

1. Place `data_ready-v4.dta` in `data/`
2. Open `BirthLottery.Rproj`
3. Run `code/1_master_analysis.R`

This is the single entry point for the full analysis and all robustness checks. By default it runs all five countries; change the `countries` vector near the top of the script to run a single country for testing (e.g. `countries <- c("AUSTRALIA")`).

**Note:** The full analysis is computationally intensive. With all five countries and default CV settings (`n_repeats = 3`, `folds_per_rep = 5`), expect several hours on a modern multi-core machine. The script parallelizes automatically using all available cores minus one.

---

## Script descriptions

| Script | Role |
|---|---|
| `1_master_analysis.R` | Entry point — sets paths and parameters, sources all other scripts in sequence |
| `2_cleaningcode.R` | Feature engineering: missingness flags, dummy coding, outcome construction |
| `3_superlearner_withobs.R` | Core engine: parallelized SuperLearner across all outcome × country × fold combinations |
| `4_OLS_logit_withobs.R` | Robustness: OLS and logistic regression comparison (appendix) |
| `5_psid.R` | Robustness: enriched PSID predictors for USA (race, wealth, health, etc.) |
| `6_downsample.R` | Robustness: downsampling USA to smaller-country sample sizes |
| `8_figures.R` | Standalone: reads output CSVs and produces all paper figures |

---

## Output file naming

Main results follow this convention:

```
table_<outcome>-<group>_<pred_set>_SuperLearner.csv
```

For example: `table_poverty-all_predictors017_SuperLearner.csv`

Robustness files append a tag before `_SuperLearner`: `_psid`, `_minobs3`, `_OLS`, `_Logit`.

**Predictor sets:**

| Name | Contents |
|---|---|
| `famincedu` | Childhood income deciles + parental education (benchmark model) |
| `predictors010` | All CNEF harmonized predictors measured ages 0–10 |
| `predictors017` | All CNEF harmonized predictors measured ages 0–17 (full model) |

**Outcome groups:**

| Group | Sample |
|---|---|
| `all` | Full country sample |
| `childbottom20` | Children from bottom 20% of income distribution |
| `childtop20` | Children from top 20% of income distribution |

