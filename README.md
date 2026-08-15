# Replication Code: Predicting the Birth Lottery

This repository contains the replication code and results for:

> Hastings & Parolin. *Rags or Riches? Predicting Life Outcomes from the Birth Lottery Across Five High-Income Countries.*

---

## Overview

This project predicts adult life outcomes from childhood factors in five high-income countries: the United States, Germany, Australia, South Korea, and the United Kingdom.

**Outcomes predicted:** poverty in adulthood, top 10% income, years of education, and adult income decile rank. Mobility analyses predict upward and downward mobility for children born into the bottom and top 20% of the income distribution.

---

## Data access

The main data come from the [Cross-National Equivalent File (CNEF)](https://cnef.ehe.osu.edu/), a harmonized set of national panel surveys. Access requires registration and approval directly from CNEF. As such the authors are not able to provide these files directly.

The analysis is based on one merged and cleaned file with all the countries in the analysis, named `data_ready-v4.dta`. Place this in the `data/` folder before running any analysis scripts.

The file `data/countrydata.csv` is included. It contains country-level contextual indicators (Gini coefficient, intergenerational income elasticity, relative poverty rate, etc.) used in the cross-country correlation heatmap. The relative poverty rate is from the OECD Income Distribution Database ("2023 or latest available year"); the remaining indicators come from the sources listed in the paper's appendix.

---

## Folder structure

```
BirthLottery/
├── BirthLottery.Rproj     # Open this in RStudio first
├── code/                  # All R scripts
├── data/                  # Data files (add CNEF .dta files here)
└── output/
    ├── results/           # LIVE output CSVs (main analysis + robustness)
    │   └── robustness/    # Robustness check CSVs
    └── figures/           # LIVE paper figures (PDFs)
```

Pre-computed results CSVs are included in `output/results/` so that figures can be reproduced without re-running the full analysis (which is computationally intensive).

---

## Getting started

**Open `BirthLottery.Rproj` in RStudio.** This sets the working directory. All scripts use the `here` package to build paths relative to the project root, so they will work regardless of where the folder is stored on your machine.

### Required R packages

Install any missing packages before running:

```r
install.packages(c(
  "tidyverse", "haven", "caret", "glmnet",
  "SuperLearner", "ranger", "xgboost",
  "doParallel", "foreach", "here"
))

# One figure package not on CRAN:
devtools::install_github("coolbutuseless/ggpattern")
```

### Reproducing the figures

To reproduce the paper figures from the pre-computed results:

1. Open `BirthLottery.Rproj`
2. Run `code/7_figures.R`

Figures are saved as PDFs to `output/figures/`.

### Re-running the full analysis

To re-run the analysis from scratch (requires the CNEF data files):

1. Place `data_ready-v4.dta` in `data/`
2. Open `BirthLottery.Rproj`
3. Run `code/1_master_analysis.R`

This is the single entry point for the full analysis and all robustness checks. By default it runs all five countries.

**Note:** The full analysis is computationally intensive. With all five countries and the CV settings used (`n_repeats = 3`, `folds_per_rep = 5`), it takes approximately two hours on the personal computer used by one of the authors. The script parallelizes automatically using all available cores minus one.

---

## Script descriptions

| Script | Role |
|---|---|
| `1_master_analysis.R` | Entry point — sets paths and parameters, sources all other scripts in sequence |
| `2_cleaningcode.R` | Feature engineering: missingness flags, dummy coding, outcome construction |
| `3_superlearner_withobs.R` | Core engine: parallelized SuperLearner across all outcome × country × predictor-set × fold combinations |
| `4_OLS_logit_withobs.R` | Robustness: OLS and logistic regression comparison (appendix) |
| `5_psid.R` | Robustness: enriched PSID predictors for USA (race, wealth, health, incarceration, etc.) |
| `6_downsample.R` | Robustness: downsampling USA to match smaller-country sample sizes |
| `7_figures.R` | Standalone: reads output CSVs and produces all paper figures |

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
