# 8_figures.R — All six paper figures
# Standalone script: reads output/ and robustness/ CSVs; saves to output/figures/
#
# Required packages (install once if missing):
#   tidyverse, haven, here
#   ggpattern  — devtools::install_github("coolbutuseless/ggpattern")
#   ggflags    — remotes::install_github("jimjam-slam/ggflags")

library(tidyverse)
library(ggpattern)
library(ggflags)
library(haven)
library(here)

# ---- Paths ----------------------------------------------------------------
output_dir     <- here("output", "results")
robustness_dir <- here("output", "results", "robustness")
fig_dir        <- here("output", "figures")
scripts        <- here("code")
dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Color palette --------------------------------------------------------
# To restyle all figures at once, change the three hex codes here.
col_bench  <- "#30598a"  # dark blue  — benchmark: family income & education
col_mid    <- "#72bfed"  # light blue — + predictors ages 0-10
col_full   <- "#e27a37"  # orange     — full predictors ages 0-17
col_bar    <- "gray70"   # background bar in figures 1 & 2

# Named vectors used in scale_color/shape_manual throughout
pred_cols <- c(
  "family income & education" = col_bench,
  "+ predictors (ages 0-10)"  = col_mid,
  "+ predictors (ages 0-17)"  = col_full
)
pred_shapes <- c(
  "family income & education" = 17,
  "+ predictors (ages 0-10)"  = 16,
  "+ predictors (ages 0-17)"  = 15
)

# ---- Shared helpers -------------------------------------------------------

fmt_country    <- function(x) ifelse(x %in% c("USA", "UK"), x, str_to_title(tolower(x)))
country_levels <- c("UK", "Korea", "Australia", "Germany", "USA")
outcomes_main  <- c("poverty", "top10", "education", "adcont")
pred_sets_main <- c("famincedu", "predictors010", "predictors017")

# Reads one table CSV; returns NULL if absent (skipped country/group combos)
read_table <- function(dir, outcome, group, pred_set, tag = "") {
  path <- file.path(
    dir,
    paste0("table_", outcome, "-", group, "_", pred_set, tag, "_SuperLearner.csv")
  )
  if (!file.exists(path)) return(NULL)
  read_csv(path, show_col_types = FALSE)
}

base_theme <- function() {
  theme_minimal() +
    theme(
      strip.background = element_rect(fill = "gray90", color = NA),
      strip.text       = element_text(face = "bold"),
      axis.text.y      = element_text(size = 10),
      legend.position  = "bottom",
      legend.direction = "horizontal"
    )
}

pred_set_key <- function(ps) {
  case_when(
    ps == "famincedu"     ~ "family income & education",
    ps == "predictors010" ~ "+ predictors (ages 0-10)",
    ps == "predictors017" ~ "+ predictors (ages 0-17)",
    TRUE                  ~ NA_character_
  )
}

# ============================================================
# Figure 1 — Full-sample predictability (fig-main)
# ============================================================

panel_labels_main <- c(
  p1 = "A: Poverty",
  p2 = "B: Top 10%",
  p3 = "C: Education",
  p4 = "D: Income Decile"
)

outcome_panel_main <- c(
  poverty   = "p1",
  top10     = "p2",
  education = "p3",
  adcont    = "p4"
)

df_main <- map_dfr(outcomes_main, function(out) {
  map_dfr(pred_sets_main, function(ps) {
    read_table(output_dir, out, "all", ps) |>
      mutate(pred_set = ps, outcome = out)
  })
}) |>
  mutate(
    Country = fmt_country(Country),
    Country = factor(Country, levels = country_levels),
    key     = factor(pred_set_key(pred_set), levels = names(pred_cols)),
    Panel   = factor(outcome_panel_main[outcome], levels = names(panel_labels_main))
  ) |>
  filter(!(pred_set == "predictors010" & Country == "Korea")) |>
  filter(!is.na(key))

df_bars_main <- df_main |> filter(pred_set == "predictors017")

ggplot() +
  geom_vline(xintercept = 0, linewidth = .5, linetype = "dashed") +
  geom_segment(
    data = df_bars_main,
    aes(x = 0, xend = SuperLearner, y = Country, yend = Country),
    color = col_bar, linewidth = 4
  ) +
  geom_point(
    data = df_main,
    aes(x = SuperLearner, y = Country, shape = key, color = key),
    size = 5, alpha = 0.8
  ) +
  facet_wrap(~ Panel, ncol = 2, labeller = labeller(Panel = panel_labels_main)) +
  scale_color_manual(values = pred_cols) +
  scale_shape_manual(values = pred_shapes) +
  base_theme() +
  labs(x = expression(R^2), y = "Country", color = NULL, shape = NULL)

ggsave(file.path(fig_dir, "plot_fullsample_bars.pdf"),
       width = 8, height = 8, units = "in")
cat("Saved: plot_fullsample_bars.pdf\n")

# Alternate version — grouped bars (one bar per predictor set per country)
# complete() adds NA rows for Korea's missing ages 0-10 so all bars are equal width
df_main_bars <- df_main |>
  complete(Country, Panel, key)

ggplot(df_main_bars, aes(x = SuperLearner, y = Country, fill = key)) +
  geom_vline(xintercept = 0, linewidth = .5, linetype = "dashed") +
  geom_col(
    position = position_dodge(width = 0.7),
    width    = 0.6,
    alpha    = 0.85
  ) +
  facet_wrap(~ Panel, ncol = 2, labeller = labeller(Panel = panel_labels_main)) +
  scale_fill_manual(values = pred_cols) +
  base_theme() +
  labs(x = expression(R^2), y = "Country", fill = NULL) +
  guides(fill = guide_legend(reverse = TRUE))

ggsave(file.path(fig_dir, "plot_fullsample_bars_v2.pdf"),
       width = 8, height = 8, units = "in")
cat("Saved: plot_fullsample_bars_v2.pdf\n")

# ============================================================
# Figure 2 — Mobility (fig-mobility)
# ============================================================

mobility_spec <- list(
  list(out = "top50",    grp = "childbottom20", panel = "p1",
       label = "A: Upward Mobility\n(top 50% for child bottom 20%)"),
  list(out = "poverty",  grp = "childbottom20", panel = "p2",
       label = "B: Persistence of Poverty\n(poverty from bottom 20%)"),
  list(out = "bottom50", grp = "childtop20",    panel = "p3",
       label = "C: Downward Mobility\n(bottom 50% for child top 20%)"),
  list(out = "top20",    grp = "childtop20",    panel = "p4",
       label = "D: Persistence of Riches\n(top 20% for child top 20%)")
)

panel_labels_mob <- set_names(
  map_chr(mobility_spec, ~ .x$label),
  map_chr(mobility_spec, ~ .x$panel)
)

df_mob <- map_dfr(mobility_spec, function(s) {
  map_dfr(pred_sets_main, function(ps) {
    read_table(output_dir, s$out, s$grp, ps) |>
      mutate(pred_set = ps, panel = s$panel)
  })
}) |>
  mutate(
    Country = fmt_country(Country),
    Country = factor(Country, levels = country_levels),
    key     = factor(pred_set_key(pred_set), levels = names(pred_cols)),
    panel   = factor(panel, levels = names(panel_labels_mob))
  ) |>
  filter(!(pred_set == "predictors010" & Country == "Korea")) |>
  filter(!is.na(key))

df_bars_mob <- df_mob |> filter(pred_set == "predictors017")

ggplot() +
  geom_vline(xintercept = 0, linewidth = .5, linetype = "dashed") +
  geom_segment(
    data = df_bars_mob,
    aes(x = 0, xend = SuperLearner, y = Country, yend = Country),
    color = col_bar, linewidth = 4
  ) +
  geom_point(
    data = df_mob,
    aes(x = SuperLearner, y = Country, shape = key, color = key),
    size = 5, alpha = 0.8
  ) +
  facet_wrap(~ panel, ncol = 2, labeller = labeller(panel = panel_labels_mob)) +
  scale_color_manual(values = pred_cols) +
  scale_shape_manual(values = pred_shapes) +
  base_theme() +
  labs(x = expression(R^2), y = "Country", color = NULL, shape = NULL)

ggsave(file.path(fig_dir, "plot_mobility_bars.pdf"),
       width = 8, height = 8, units = "in")
cat("Saved: plot_mobility_bars.pdf\n")

# ============================================================
# Figure 3 — Downsampling (fig-downsample)
# ============================================================

panel_labels_ds <- c(
  p1 = "A: Poverty",
  p2 = "B: Top 10%",
  p3 = "C: Education",
  p4 = "D: Income Decile"
)

outcome_panel_ds <- c(poverty = "p1", top10 = "p2", education = "p3", adcont = "p4")

df_ds_raw <- read_csv(
  file.path(robustness_dir, "downsample_r2_summary.csv"),
  show_col_types = FALSE
) |>
  rename(Downsampled = R2_CV_Mean, `True Test` = R2_Holdout_Mean) |>
  mutate(Sample_Size = as.character(Sample_Size))

df_full_usa <- map_dfr(outcomes_main, function(out) {
  read_table(output_dir, out, "all", "predictors017") |>
    filter(Country == "USA") |>
    transmute(
      Outcome     = out,
      Downsampled = SuperLearner,
      `True Test` = NA_real_,
      Sample_Size = "Full"
    )
})

df_ds_plot <- bind_rows(df_ds_raw, df_full_usa) |>
  pivot_longer(c(Downsampled, `True Test`), names_to = "Metric", values_to = "Value") |>
  mutate(
    Sample_Size = factor(Sample_Size, levels = c("418", "1843", "2765", "Full")),
    Panel       = factor(outcome_panel_ds[Outcome], levels = names(panel_labels_ds))
  ) |>
  arrange(Panel, Metric, Sample_Size)

ggplot(df_ds_plot, aes(x = Value, y = Sample_Size, color = Metric, group = Metric)) +
  geom_point(aes(shape = Metric), size = 3, alpha = .9, stroke = 1.5, na.rm = TRUE) +
  geom_path(na.rm = TRUE) +
  facet_wrap(~ Panel, ncol = 2, labeller = labeller(Panel = panel_labels_ds)) +
  scale_color_manual(values = c("Downsampled" = col_bench, "True Test" = col_full)) +
  scale_shape_manual(values = c("Downsampled" = 15, "True Test" = 16)) +
  base_theme() +
  labs(x = expression(R^2), y = "Sample Size", color = NULL, shape = NULL)

ggsave(file.path(fig_dir, "USA_downsampling_plot.pdf"),
       width = 8, height = 8, units = "in")
cat("Saved: USA_downsampling_plot.pdf\n")

# ============================================================
# Figure 4 — PSID enriched predictors (fig-more-vars)
# ============================================================

outcome_labels_psid <- c(
  poverty   = "Poverty",
  adcont    = "Income Decile",
  top10     = "Top 10%",
  education = "Education"
)

df_psid_enriched <- map_dfr(outcomes_main, function(out) {
  read_table(robustness_dir, out, "all", "predictorsusa", tag = "_psid") |>
    filter(Country == "USA") |>
    transmute(Outcome = out, SuperLearner, Group = "Additional")
})

df_psid_original <- map_dfr(outcomes_main, function(out) {
  read_table(output_dir, out, "all", "predictors017") |>
    filter(Country == "USA") |>
    transmute(Outcome = out, SuperLearner, Group = "Original")
})

df_psid <- bind_rows(df_psid_enriched, df_psid_original) |>
  mutate(
    Outcome = factor(outcome_labels_psid[Outcome],
                     levels = c("Income Decile", "Education", "Top 10%", "Poverty")),
    Group   = factor(Group, levels = c("Additional", "Original"))
  )

ggplot(df_psid, aes(y = Outcome, x = SuperLearner, fill = Group, pattern = Group)) +
  geom_bar_pattern(
    stat                   = "identity",
    position               = position_dodge(width = 0.6),
    width                  = 0.5,
    color                  = "black",
    pattern_colour         = "black",
    pattern_fill           = "black",
    pattern_angle          = -45,
    pattern_spacing        = 0.02,
    pattern_density        = 0.1,
    pattern_size           = 0.3,
    pattern_key_scale_factor = 0.7
  ) +
  scale_fill_manual(values = c("Original" = col_bench, "Additional" = col_full)) +
  scale_pattern_manual(values = c("Original" = "none", "Additional" = "stripe")) +
  theme_minimal(base_size = 14) +
  theme(
    panel.grid.major.y = element_blank(),
    strip.text         = element_text(face = "bold"),
    legend.title       = element_blank(),
    legend.position    = "bottom"
  ) +
  labs(y = "Outcome", x = expression(R^2)) +
  guides(fill = guide_legend(reverse = TRUE), pattern = guide_legend(reverse = TRUE))

ggsave(file.path(fig_dir, "USA_psid_plot.pdf"),
       width = 7, height = 4.5, units = "in")
cat("Saved: USA_psid_plot.pdf\n")

# ============================================================
# Figure 5 — Explanation vs Prediction (fig-example)
# ============================================================

df <- read_dta(here("data", "data_ready-v4.dta")) |>
  rename(
    poverty       = poverty_2426,
    education     = years_of_edu,
    child_obs     = obsage_017_c,
    edu_years_mom = edu_attain_mom_years,
    edu_years_dad = edu_attain_dad_years
  )
source(file.path(scripts, "2_cleaningcode.R"))

df_usa <- df |>
  filter(country == "USA") |>
  drop_na(chcont, adcont)

ggplot(df_usa, aes(factor(chcont), adcont)) +
  geom_point(
    alpha    = .6,
    color    = col_mid,
    position = position_jitter(width = 0.2, height = 0.2),
    size     = .2
  ) +
  stat_summary(color = col_full) +
  stat_summary(
    fun.data = "mean_cl_normal",
    geom     = "errorbar",
    width    = .4,
    color    = col_full
  ) +
  scale_y_continuous(breaks = 1:10, limits = c(0.5, 10.5)) +
  theme_minimal() +
  labs(
    x       = "Child Income Decile",
    y       = "Adult Income Decile",
    caption = "Source: CNEF/Panel Study of Income Dynamics (USA)"
  )

ggsave(file.path(fig_dir, "explanation_vs_prediction_income.pdf"),
       width = 8, height = 6, units = "in")
cat("Saved: explanation_vs_prediction_income.pdf\n")

# ============================================================
# Figure 6 — Gini & IGE (fig-other)
# ============================================================

abbrevs <- tibble(
  Country = c("USA", "GERMANY", "AUSTRALIA", "KOREA", "UK"),
  Code    = c("us", "de", "au", "kr", "gb")
)

comparisons <- read_csv(
  here("data", "otherdata_Sept.csv"),
  show_col_types = FALSE
) |>
  mutate(Country = case_when(
    Country == "South Korea"   ~ "KOREA",
    Country == "United States" ~ "USA",
    Country == "United Kingdom"~ "UK",
    TRUE                       ~ toupper(Country)
  )) |>
  filter(Country != "Switzerland")

outcome_labels_other <- c(
  poverty   = "Poverty",
  top10     = "Top 10% Income",
  education = "Education",
  adcont    = "Income Decile"
)

df_other <- map_dfr(outcomes_main, function(out) {
  read_table(output_dir, out, "all", "predictors017") |>
    mutate(
      Country = toupper(Country),
      R2_Type = factor(
        outcome_labels_other[[out]],
        levels = c("Poverty", "Top 10% Income", "Education", "Income Decile")
      )
    ) |>
    rename(R2 = SuperLearner) |>
    left_join(comparisons, by = "Country") |>
    left_join(abbrevs, by = "Country")
})

df_grid <- df_other |>
  select(R2_Type, R2, Code, gini_2020, IGE_gdim) |>
  pivot_longer(c(gini_2020, IGE_gdim), names_to = "Metric", values_to = "X") |>
  mutate(
    Metric = factor(
      Metric,
      levels = c("gini_2020", "IGE_gdim"),
      labels = c("Income Inequality (Gini)", "Intergenerational Mobility (Elasticity)")
    )
  )

lab_grid <- df_grid |>
  filter(!is.na(X), !is.na(R2)) |>
  group_by(R2_Type, Metric) |>
  reframe(
    n = n(),
    r = if (n >= 3) cor(X, R2, use = "complete.obs") else NA_real_
  ) |>
  left_join(
    df_grid |>
      group_by(R2_Type, Metric) |>
      summarise(
        label_x = max(X, na.rm = TRUE) - 0.05 * diff(range(X, na.rm = TRUE)),
        label_y = min(R2, na.rm = TRUE) + 0.05 * diff(range(R2, na.rm = TRUE)),
        .groups = "drop"
      ),
    by = c("R2_Type", "Metric")
  ) |>
  mutate(label = ifelse(is.na(r), "r = NA",
                        paste0("r = ", formatC(r, digits = 2, format = "f"))))

ggplot(df_grid, aes(x = X, y = R2)) +
  geom_smooth(method = "lm", se = FALSE, color = "gray50", linetype = "dashed") +
  geom_flag(aes(country = Code), size = 10) +
  geom_text(
    data = lab_grid,
    aes(x = label_x, y = label_y, label = label),
    hjust = 1, vjust = 0, size = 5, fontface = "bold"
  ) +
  facet_grid(rows = vars(R2_Type), cols = vars(Metric), scales = "free") +
  theme_minimal() +
  theme(
    strip.background = element_rect(fill = "gray90", color = NA),
    strip.text       = element_text(face = "bold"),
    axis.text.y      = element_text(size = 10)
  ) +
  labs(x = NULL, y = expression("Predictability (SuperLearner " * R^2 * ")"))

ggsave(file.path(fig_dir, "r2_grid_gini_IGE.pdf"),
       width = 8, height = 11, units = "in")
cat("Saved: r2_grid_gini_IGE.pdf\n")

# ============================================================
# Figure 7 — Correlation heatmap (fig-corr-heatmap)
# ============================================================

heat_factors <- c(
  gini_2020                    = "Gini Coefficient",
  IGE_gdim                     = "IGE of Income (GDIM)",
  IGPOV                        = "IGE of Poverty",
  edu_cor                      = "Correlation of Education",
  Relative_Poverty_Rate        = "Relative Poverty Rate",
  IOP                          = "Inequality of Opportunity Index",
  Global_Social_Mobility_Index = "Global Social Mobility Index"
)

heat_outcome_levels <- c("Poverty", "Top 10%", "Education", "Income Decile")

heat_outcome_labels <- c(
  poverty   = "Poverty",
  top10     = "Top 10%",
  education = "Education",
  adcont    = "Income Decile"
)

df_heat_long <- map_dfr(outcomes_main, function(out) {
  read_table(output_dir, out, "all", "predictors017") |>
    mutate(Country = toupper(Country), outcome = out) |>
    rename(R2 = SuperLearner) |>
    left_join(comparisons, by = "Country")
})

df_cors <- map_dfr(outcomes_main, function(out) {
  sub <- df_heat_long |> filter(outcome == out)
  map_dfr(names(heat_factors), function(fac) {
    x    <- sub[[fac]]
    y    <- sub$R2
    keep <- !is.na(x) & !is.na(y)
    n    <- sum(keep)
    r    <- if (n >= 3) cor(x[keep], y[keep]) else NA_real_
    tibble(outcome = out, factor = fac, r = r, n = n)
  })
}) |>
  mutate(
    outcome_label = factor(heat_outcome_labels[outcome], levels = heat_outcome_levels),
    factor_label  = factor(heat_factors[factor], levels = rev(heat_factors))
  )

ggplot(df_cors, aes(x = outcome_label, y = factor_label, fill = r)) +
  geom_tile(color = "white", linewidth = 0.8) +
  geom_text(
    aes(label = ifelse(is.na(r), "–", sprintf("%.2f", r))),
    size = 11 / .pt, fontface = "bold",
    color = ifelse(abs(df_cors$r) > 0.6, "white", "gray20")
  ) +
  scale_fill_gradient2(
    low      = col_bench,   # dark blue
    mid      = "white",
    high     = col_full,    # orange
    midpoint = 0,
    limits   = c(-1, 1),
    name     = "r",
    na.value = "gray85"
  ) +
  scale_x_discrete(position = "top") +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x     = element_text(angle = 0, hjust = 0.5, vjust = 0),
    axis.text.y     = element_text(hjust = 1),
    panel.grid      = element_blank(),
    legend.position = "right"
  ) +
  labs(x = NULL, y = NULL)

ggsave(file.path(fig_dir, "correlation_heatmap.pdf"),
       width = 8, height = 3.8, units = "in")
cat("Saved: correlation_heatmap.pdf\n")

# ============================================================
# Figure A1 — Robustness: minobs3 (appendix)
# ============================================================
# Shows original full-model results alongside the ≥3 childhood observations
# robustness check.

panel_labels_rob <- c(
  p1 = "A: Poverty",
  p2 = "B: Top 10%",
  p3 = "C: Education",
  p4 = "D: Income Decile"
)

outcome_panel_rob <- c(poverty = "p1", top10 = "p2", education = "p3", adcont = "p4")

rob_cols <- c(
  "Original"           = col_full,
  "≥3 childhood obs." = col_bench
)
rob_shapes <- c(
  "Original"           = 15,
  "≥3 childhood obs." = 17
)

read_rob_table <- function(outcome, tag) {
  path <- file.path(
    robustness_dir,
    paste0("table_", outcome, "-all_predictors017_", tag, "_SuperLearner.csv")
  )
  if (!file.exists(path)) return(NULL)
  read_csv(path, show_col_types = FALSE)
}

df_rob_original <- map_dfr(outcomes_main, function(out) {
  read_table(output_dir, out, "all", "predictors017") |>
    mutate(outcome = out, check = "Original")
})

df_rob_minobs3 <- map_dfr(outcomes_main, function(out) {
  read_rob_table(out, "minobs3") |>
    mutate(outcome = out, check = "≥3 childhood obs.")
})

df_rob <- bind_rows(df_rob_original, df_rob_minobs3) |>
  mutate(
    Country = fmt_country(Country),
    Country = factor(Country, levels = country_levels),
    check   = factor(check, levels = rev(names(rob_cols))),
    Panel   = factor(outcome_panel_rob[outcome], levels = names(panel_labels_rob))
  )

ggplot(df_rob, aes(x = SuperLearner, y = Country, fill = check)) +
  geom_vline(xintercept = 0, linewidth = .5, linetype = "dashed") +
  geom_col(
    position = position_dodge(width = 0.7),
    width    = 0.6,
    alpha    = 0.85
  ) +
  geom_text(
    aes(x = pmax(SuperLearner, 0), label = scales::comma(Sample_Size)),
    position = position_dodge(width = 0.7),
    hjust    = -0.15,
    size     = 2.5
  ) +
  facet_wrap(~ Panel, ncol = 2, labeller = labeller(Panel = panel_labels_rob)) +
  scale_fill_manual(values = rob_cols) +
  scale_x_continuous(expand = expansion(mult = c(0.02, 0.25))) +
  base_theme() +
  labs(x = expression(R^2), y = "Country", fill = NULL) +
  guides(fill = guide_legend(reverse = TRUE))

ggsave(file.path(fig_dir, "plot_robustness_minobs.pdf"),
       width = 8, height = 9, units = "in")
cat("Saved: plot_robustness_minobs.pdf\n")
