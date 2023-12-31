# 为了更方便的利用NMF代替EPA PMF进行污染物源解析
# Email: qs_wang@shu.edu.cn
# 欢迎使用
################################################################################ Function to generate the report PDF
packages_to_load <- c("ggrepel", "scales", "gridExtra", "grid", "reshape2", "magrittr", "NMF", 
                      "cluster", "dplyr", "readxl", "ggplot2", "patchwork", "openxlsx", 
                      "tidyverse", "eoffice", "corrplot", "lubridate")

# 安装和加载缺失的包
install_and_load_package <- function(package_name) {
  if (!requireNamespace(package_name, quietly = TRUE)) {
    install.packages(package_name, dependencies = TRUE)
  }
  library(package_name, character.only = TRUE)
}

invisible(lapply(packages_to_load, install_and_load_package))
################################################################################ Color list
factorcolor = c("#1f78b4", "#33a02c", "#e31a1c", "#ff7f00", "#6a3d9a", "#a6cee3", "#b2df8a", "#fb9a99", "#fdbf6f", "#cab2d6")
################################################################################ Save results as PDF
generate_report_pdf <- function(output_path, file_suffix, title_main, title_author, algorithm, seed, rank, nrun) {
  # Construct the full file name
  file_name <- paste0("NMF-report", "_",file_suffix, ".pdf")  # Replace "YOUR_PREFIX_" with your desired prefix
  
  # Generate PDF
  pdf(file.path(output_path, file_name), paper="a4", onefile = TRUE)
  
  # Plotting code (unchanged)
  plot.new()
  title("Reports", cex.main = 8, line = -6, col.main = "black", family = "serif")
  title("Automatically generated by NMF", cex.main = 2, line = -10, col.main = "black", family = "serif")
  title(title_author, cex.main = 2, line = -13, col.main = "black", family = "serif")
  title(format(Sys.Date(), "%Y-%m-%d"), cex.main = 2, line = -15, col.main = "black", family = "serif")
  mtext(paste("Algorithm: '", algorithm, "'", sep = ""), side = 3, line = -20, cex = 1, col = "gray")
  mtext(paste("Seed: '", seed, "'", sep = ""), side = 3, line = -21, cex = 1, col = "gray")
  mtext(paste("Rank: '", rank, "'", sep = ""), side = 3, line = -22, cex = 1, col = "gray")
  mtext(paste("nrun: '", nrun, "'", sep = ""), side = 3, line = -23, cex = 1, col = "gray")
  }

################################################################################ Export data
export_data <- function(output_folder, file_suffix, datasets, sheet_names) {
  file_name <- paste("NMF-OUTPUT", "_", file_suffix, ".xlsx", sep = "")
  full_file_path <- file.path(output_folder, file_name)
  wb <- createWorkbook()
  for (i in seq_along(datasets)) {
    addWorksheet(wb, sheetName = sheet_names[i])
    writeData(wb, sheet = sheet_names[i], x = datasets[[i]])
  }
  saveWorkbook(wb, file = full_file_path, overwrite = TRUE)
  cat("File exported to:", full_file_path, "\n")
}

################################################################################ NMF Output data Post-Processing
nmf_postprocess <- function(rawdata, vc_factor) {
  H = res@fit@H
  W = res@fit@W
  W <- as.matrix(W * vc_factor[, rep(1, ncol(W))])
  V = W %*% H
  V = cbind(rawdata[, 1], V)
  names(V) = names(rawdata)
  # Matrix, MS, TS
  result = vector("list", ncol(W))
  MS = H
  TS = W
  upper_MS = H
  lower_MS = H
  for (i in 1:ncol(W)) {
    result[[i]] = W[, i] %*% t(H[i, ])
    MS[i,] = colMeans(result[[i]])
    upper_MS[i,] = apply(result[[i]], 2, function(x) quantile(x, probs = 0.9))
    lower_MS[i,] = apply(result[[i]], 2, function(x) quantile(x, probs = 0.1))
    TS[,i] = rowSums(result[[i]])
  }
  MS = t(MS)
  colnames(MS) = paste0("N", 1:(ncol(MS)))
  MS = cbind(colnames(rawdata[,2:ncol(rawdata)]), MS)
  colnames(MS)[1] = "Dp"
  MS <- data.frame(MS)
  upper_MS = t(upper_MS)
  colnames(upper_MS) = paste0("N", 1:(ncol(upper_MS)))
  upper_MS = cbind(colnames(rawdata[,2:ncol(rawdata)]), upper_MS)
  colnames(upper_MS)[1] = "Dp"
  upper_MS <- data.frame(upper_MS)
  lower_MS = t(lower_MS)
  colnames(lower_MS) = paste0("N", 1:(ncol(lower_MS)))
  lower_MS = cbind(colnames(rawdata[,2:ncol(rawdata)]), lower_MS)
  colnames(lower_MS)[1] = "Dp"
  lower_MS <- data.frame(lower_MS)
  colnames(TS) = paste0("N", 1:(ncol(TS)))
  TS = cbind(rawdata[, 1], TS)
  # Daily trend
  diel_variations = TS
  diel_variations$hour <- hour(diel_variations$date)  
  diel_variations <- diel_variations %>% 
    group_by(hour) %>% 
    summarise_all(mean) %>% 
    select(-2) %>% 
    ungroup() %>%
    mutate(across(-hour, list(lower = ~quantile(., probs = 0.1), upper = ~quantile(., probs = 0.9))))
  # Return a list of variables
  return(list(H = H, W = W, V = V, MS = MS, TS = TS, upper_MS = upper_MS, lower_MS = lower_MS, diel_variations = diel_variations, result = result))
}

# Heat map of correlations between factors
factor_corrplot <- function(data) {
  # Assuming 'data' is a data frame with numeric columns
  corr <- cor(as.data.frame(lapply(data[, 2:ncol(data)], as.numeric)), 
              use = "pairwise.complete.obs", method = "pearson")
  
  corrplot(corr = corr, method = "square", type = "upper", bg = "white",
           is.corr = TRUE, diag = TRUE, outline = TRUE, order = "original",
           tl.col = "black")
  }

################################################################################ Scatter plot of NMF simulation effect
scatterplot_matrix <- function(rawdata, V) {
  x <- as.data.frame(lapply(rawdata[, 2:ncol(rawdata)], as.numeric))
  y <- as.data.frame(lapply(V[, 2:ncol(V)], as.numeric))
  
  # Reshape data into long format
  x_long <- melt(x, id.vars = NULL)
  y_long <- melt(y, id.vars = NULL)
  combined_data <- cbind(x_long, y_long$value)
  colnames(combined_data)[2:3] <- c("Obs", "NMF")
  
  # Plot
  plot_list <- list()
  for (variable in unique(combined_data$variable)) {
    data_subset <- combined_data[combined_data$variable == variable, ]
    plot <- ggplot(data_subset, aes(x = Obs, y = NMF)) +
      geom_point(color = "#1e8b9b") +
      geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "black", linewidth = 1) +
      coord_cartesian(xlim = c(min(data_subset$Obs, data_subset$NMF), max(data_subset$Obs, data_subset$NMF)), 
                      ylim = c(min(data_subset$Obs, data_subset$NMF), max(data_subset$Obs, data_subset$NMF))) +
      theme_minimal() +
      theme(aspect.ratio = 1) +
      ggtitle(NULL) +
      theme(axis.text = element_blank(), axis.title = element_blank(), panel.border = element_rect(color = "black", fill = NA)) +
      annotate("text", x = min(data_subset$Obs), y = max(data_subset$NMF), label = variable, hjust = 0, vjust = 1, size = 4, color = "black")
    plot_list[[variable]] <- plot
  }
  
  grid.arrange(grobs = plot_list, ncol = 7, 
               bottom = textGrob(expression(Obs._Conc.~(μg/m^{3})), gp = gpar(fontsize = 18)),
               left = textGrob(expression(NMF_Conc.~(μg/m^{3})), rot = 90, gp = gpar(fontsize = 18)))
}

################################################################################ Scatter plot of NMF simulation effect
scatterplot_matrixt <- function(rawdata, V) {
  # Convert rawdata and V to numeric data frames
  x <- as.data.frame(lapply(rawdata[, 2:ncol(rawdata)], as.numeric))
  y <- as.data.frame(lapply(V[, 2:ncol(V)], as.numeric))
  
  # Create a data frame with row sums of x and y
  sum_df <- data.frame(rowSums(x), rowSums(y))
  
  # Fit a linear model
  lm_model <- lm(rowSums(y) ~ rowSums(x), data = sum_df)
  slope <- coef(lm_model)[2]
  intercept <- coef(lm_model)[1]
  r_squared <- summary(lm_model)$r.squared
  
  # Plot
  ggplot(sum_df, aes(x = rowSums(x), y = rowSums(y))) +
    geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "black", linewidth = 1) +
    geom_point(shape = 20, size = 6, color = "#1e8b9b", fill = "#1e8b9b") +
    geom_smooth(aes(color = "Regression Line"), method = "lm", se = FALSE, size = 1.1) +
    labs(x = expression(Obs._Conc.~(μg/m^{3})), y = expression(NMF_Conc.~(μg/m^{3}))) +
    theme_minimal() +
    theme(
      axis.text = element_text(size = 18, vjust = 0.5),
      axis.title = element_text(size = 18, vjust = 1),
      panel.border = element_rect(color = "black", fill = NA, size = 1.2),
      axis.ticks = element_line(color = "black", size = 1.2),
      axis.ticks.length = unit(0.2, "cm"),
      legend.position = c(0.3, 0.9),
      legend.box = "vertical",
      legend.title = element_blank(),
      legend.text = element_text(size = 12),
      legend.margin = margin(t = 0, r = 0, b = 0, l = 0),
      legend.key.size = unit(2, "lines")
    ) +
    scale_x_continuous(expand = c(0, 2), limits = c(0, 1.1 * max(c(max(rowSums(x)), max(rowSums(y)))))) +
    scale_y_continuous(expand = c(0, 2), limits = c(0, 1.1 * max(c(max(rowSums(x)), max(rowSums(y)))))) +
    coord_fixed(ratio = 1) +
    scale_color_manual(values = c("Regression Line" = "red4"), name = NULL)
}

################################################################################ Source profile
spplot <- function(MS, upper_MS, lower_MS) {
  # Pivot long and convert to numeric
  MS_long <- MS %>%
    pivot_longer(-Dp, names_to = "Source", values_to = "Concentration") %>%
    mutate(Concentration = as.numeric(Concentration))
  
  upper_MS_long <- upper_MS %>%
    pivot_longer(-Dp, names_to = "Source", values_to = "upper") %>%
    mutate(upper = as.numeric(upper))
  
  lower_MS_long <- lower_MS %>%
    pivot_longer(-Dp, names_to = "Source", values_to = "lower") %>%
    mutate(lower = as.numeric(lower))
  
  # Group by Dp and calculate Proportion
  MS_long <- MS_long %>% 
    group_by(Dp) %>% 
    mutate(Proportion = Concentration / sum(Concentration))
  
  # Combine data frames
  MS_long <- cbind(MS_long, upper_MS_long[, 3], lower_MS_long[, 3])
  max_upper_value <- max(MS_long$upper)
  
  # Plot
  ggplot(MS_long, aes(x = Dp)) +
    geom_col(aes(y = Proportion * max_upper_value, fill = Source), width = 0.6) +
    geom_point(aes(y = Concentration), shape = 19, size = 3.5, color = "grey1") +
    geom_errorbar(aes(ymin = lower, ymax = upper), 
                  position = position_dodge(width = 0.8), 
                  width = 0.5, color = "grey1", cex = 0.5) +
    labs(x = "") +
    theme_test(base_size = 20) +
    theme(legend.position = 'none', axis.text = element_text(color = 'black')) +
    theme(axis.text.x = element_text(angle = 45, size = 8, hjust = 1, vjust = 1),
          axis.title.x = element_text(size = 15),
          panel.grid.major.x = element_line(color = "gray", linetype = "dashed", size = 0.1),
          panel.grid.minor = element_blank(),
          panel.background = element_blank()) +
    theme(panel.spacing = unit(1, "lines")) +
    theme(panel.border = element_rect(color = "black", fill = NA, size = 1.2)) +
    facet_wrap(~ Source, ncol = 1, scales = "fixed", strip.position = "bottom") +
    scale_y_continuous(limits = c(0, 1.05 * max_upper_value), expand = c(0.02, 0),
                       sec.axis = sec_axis(~./max_upper_value, breaks = seq(0, 1, 0.5), name = "Percentage (%)"),
                       name = expression(Conc. ~ of ~ species ~(µg/m^{3}))) +
    theme(strip.text = element_blank()) +
    theme(axis.text.y.left = element_text(color = "black", size = 15)) +
    theme(axis.title.y.left = element_text(color = "black", size = 16)) +
    theme(axis.text.y.right = element_text(color = "grey", size = 15)) +
    theme(axis.title.y.right = element_text(color = "grey", size = 16)) +
    scale_x_discrete(limits = unique(MS_long$Dp)) +
    scale_fill_manual(values = factorcolor)  # 使用自定义颜色
}

################################################################################ Time variation characteristics
tsplot <- function(TS) {
  # Diurnal Plot
  TS_long <- TS %>% pivot_longer(cols = -date, names_to = "Pollutant", values_to = "Concentration") %>%
    mutate(hour = as.numeric(format(date, format = "%H")))
  
  summary_stats <- TS_long %>% 
    group_by(Pollutant, hour) %>% 
    summarise(mean = mean(Concentration), 
              lower = quantile(Concentration, probs = 0.1), 
              upper = quantile(Concentration, probs = 0.9),
              .groups = "drop")  # Specify .groups argument to drop grouping
  
  diurnalplot <- ggplot(summary_stats, aes(x = hour, y = mean, color = Pollutant)) +
    geom_line(size = 1.2) +
    labs(title = "", x = "Local time", y = expression(Conc. ~ of ~ species ~(µg/m^{3})), caption = "") +
    scale_x_continuous(expand = c(0, 0.2), breaks = seq(0, 23, 6)) +
    scale_y_continuous(expand = c(0, 0.2), limits = c(0, NA)) +
    theme_minimal() +
    facet_wrap(~ Pollutant, scales = "free_y", ncol = 1, strip.position = "bottom") +
    theme(axis.title = element_text(size = 14),
          axis.title.y = element_blank(),  
          axis.text = element_text(size = 14),
          panel.grid = element_blank(),
          strip.text = element_blank(),
          panel.spacing = unit(1, "lines"),
          panel.grid.major = element_line(color = "grey80", size = 0.1),
          panel.grid.minor = element_line(color = "grey95", size = 0.05),
          panel.border = element_rect(color = "black", fill = NA, size = 0.8),
          axis.ticks = element_line(color = "black", size = 0.8),
          axis.ticks.length = unit(0.2, "cm")
    )+
    scale_color_manual(values = factorcolor) + guides(color = "none")
  
  # Time Series Plot
  TS <- complete(TS, date = seq(min(TS$date), max(TS$date), by = "1 hour"))
  TS_long <- TS %>% pivot_longer(cols = -date, names_to = "Pollutant", values_to = "Concentration")
  TS_long$date <- as.POSIXct(TS_long$date)
  
  timeseriesplots <- ggplot(TS_long, aes(x = date, y = Concentration, color = Pollutant)) +
    geom_line(size = 1) +
    labs(title = "", x = "Date", y = expression(Conc. ~ of ~ species ~(µg/m^{3})), caption = "") +
    scale_x_datetime(date_labels = "%m/%d", date_breaks = "1 week", limits = range(TS_long$date)) +
    scale_y_continuous(expand = c(0, 1), limits = c(0, NA)) + 
    theme_minimal() +
    facet_wrap(~ Pollutant, scales = "free_y", ncol = 1) +
    theme(axis.title = element_text(size = 14),
          axis.text = element_text(size = 14),
          panel.grid = element_blank(),
          strip.text = element_blank(),
          panel.spacing = unit(1, "lines"),
          panel.grid.major = element_line(color = "grey80", size = 0.1),
          panel.grid.minor = element_line(color = "grey95", size = 0.05),
          panel.border = element_rect(color = "black", fill = NA, size = 0.8),
          axis.ticks = element_line(color = "black", size = 0.8),
          axis.ticks.length = unit(0.2, "cm")
    )+
    scale_color_manual(values = factorcolor) + guides(color = "none") 
  
  # Combine the two plots
  grid.arrange(timeseriesplots, diurnalplot, widths = c(5, 2), ncol = 2)
}

################################################################################ Percentage contribution of each factor
contributplot <- function(MS) {
  Sconcentration <- colSums(as.data.frame(lapply(MS[, 2:ncol(MS)], as.numeric)), na.rm = TRUE)
  Spercentages <- Sconcentration / sum(Sconcentration)
  Source_pie <- data.frame(Sources = names(Sconcentration), conc = Sconcentration, Spercentages = Spercentages, stringsAsFactors = FALSE)
  
  # Check if the number of unique values in Sources is less than the length of colors
  if (length(unique(Source_pie$Sources)) < length(colors)) {
    # Subset colors to match the number of unique values
    colors <- colors[1:length(unique(Source_pie$Sources))]
  }
  
  ggplot(Source_pie, aes(x = "", y = Spercentages, fill = Sources)) +
    geom_bar(stat = "identity", width = 1) +
    coord_polar("y", start = 0) +
    theme_void() +
    theme(legend.position = "right") +
    geom_text(aes(label = paste0(round(Spercentages * 100, 2), "%")), position = position_stack(vjust = 0.5), size = 4, color = "white") +
    scale_fill_manual(values = factorcolor) +
    labs(title = "Concentration of Sources", fill = "Sources") +
    theme(plot.title = element_text(hjust = 0.5),
          legend.position = "bottom")
}