# COSC 421 - Research Question 1
# Which courses occupy the most central positions in the prerequisite network?

# Run from the repository root: Rscript RQ1/RQ1_network_analysis.R

library(igraph)
library(ggplot2)
source("R/00_load_network.R")

course_data <- load_course_data()
g <- build_prereq_graph(course_data)
nodes <- course_data$nodes

in_degree <- degree(g, mode = "in", normalized = FALSE)
out_degree <- degree(g, mode = "out", normalized = FALSE)
weighted_out_degree <- strength(g, mode = "out", weights = E(g)$option_weight)
mandatory_dependents <- strength(g, mode = "out", weights = as.numeric(E(g)$hard_requirement))
# weights = NA: count shortest paths in hops. By default igraph would use the raw
# `weight` column (1/n_alternatives) as edge length, making option edges "shorter".
betweenness_full <- betweenness(g, directed = TRUE, weights = NA, normalized = TRUE)
# PageRank on the reversed graph, so importance flows from a course back to its
# prerequisites. weights = NA stops igraph using the raw `weight` column.
g_rev <- reverse_edges(g)
pagerank <- page_rank(g_rev, weights = NA)$vector
pagerank_weighted <- page_rank(g_rev, weights = E(g_rev)$option_weight)$vector

harmonic_out <- harmonic_centrality(g, mode = "out", weights = NA, normalized = TRUE)
harmonic_in <- harmonic_centrality(g, mode = "in", weights = NA, normalized = TRUE)
# Option-weighted harmonic: an edge's length is 1 / option_weight, so a required
# edge is one step and one option out of four counts as four steps.
harmonic_out_weighted <- harmonic_centrality(g, mode = "out", weights = 1 / E(g)$option_weight,
                                             normalized = TRUE)

reach <- setNames(ego_size(g, order = vcount(g), mode = "out", mindist = 1), V(g)$name)
prereq_count <- setNames(ego_size(g, order = vcount(g), mode = "in", mindist = 1), V(g)$name)

results <- data.frame(
  course = nodes$course,
  subject = nodes$subject,
  level = nodes$level,
  title = nodes$title,
  in_degree = as.integer(in_degree[nodes$course]),
  out_degree = as.integer(out_degree[nodes$course]),
  weighted_out_degree = weighted_out_degree[nodes$course],
  mandatory_dependents = as.integer(mandatory_dependents[nodes$course]),
  betweenness = betweenness_full[nodes$course],
  harmonic_out = harmonic_out[nodes$course],
  harmonic_out_weighted = harmonic_out_weighted[nodes$course],
  harmonic_in = harmonic_in[nodes$course],
  downstream_reach = as.integer(reach[nodes$course]),
  prerequisite_reach = as.integer(prereq_count[nodes$course]),
  pagerank = pagerank[nodes$course],
  pagerank_weighted = pagerank_weighted[nodes$course],
  current_calendar = nodes$in_current_calendar,
  retired = nodes$retired,
  stringsAsFactors = FALSE
)

# Composite: mean percentile rank (0 = lowest, 1 = highest) of four foundation
# measures. Betweenness is reported separately: it measures bridging, not
# foundation, and is 0 for every course without prerequisites. The option-weighted
# harmonic is used because unweighted harmonic and downstream reach both count
# courses reached only through one-of options (Spearman rho 1.00 with each other).
composite_measures <- c("weighted_out_degree", "pagerank_weighted",
                        "harmonic_out_weighted", "downstream_reach")
results$composite_score <- rowMeans(sapply(
  results[composite_measures],
  function(x) (rank(x) - 1) / (length(x) - 1)
))
results <- results[order(-results$composite_score), ]
results$composite_rank <- seq_len(nrow(results))

write.csv(results,
          output_path("tables", "rq1_centrality_results.csv"),
          row.names = FALSE)

top_20 <- head(results, 20)
write.csv(top_20,
          output_path("tables", "rq1_top20_courses.csv"),
          row.names = FALSE)

# Department structure: induced prerequisite subgraph of every subject with 10+
# courses. Path lengths are over reachable ordered pairs only.
big_subjects <- sort(names(which(table(nodes$subject) >= 10)))
department_structure <- do.call(rbind, lapply(big_subjects, function(s) {
  sg <- induced_subgraph(g, V(g)$subject == s)
  n <- vcount(sg)
  paths <- mean_distance(sg, directed = TRUE, unconnected = TRUE,
                         weights = NA, details = TRUE)
  data.frame(
    subject = s,
    courses = n,
    internal_edges = ecount(sg),
    density = edge_density(sg),
    average_path_length = paths$res,
    reachability_pct = 100 * (n * (n - 1) - paths$unconnected) / (n * (n - 1)),
    longest_shortest_path = diameter(sg, directed = TRUE, unconnected = TRUE, weights = NA)
  )
}))
write.csv(department_structure,
          output_path("tables", "rq1_department_structure.csv"),
          row.names = FALSE)

cat("Network:", vcount(g), "courses,", ecount(g), "prerequisite edges\n")
cat("Network is a DAG:", is_dag(g), "\n")
cat("\nTop 20 central courses:\n")
print(top_20[, c("composite_rank", "course", composite_measures, "composite_score")],
      row.names = FALSE)

theme_set(theme_minimal(base_size = 12))

top_betweenness <- head(results[order(-results$betweenness), ], 15)
top_betweenness$label <- factor(top_betweenness$course, levels = rev(top_betweenness$course))
p1 <- ggplot(top_betweenness, aes(x = label, y = betweenness, fill = subject)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Courses with the greatest betweenness centrality",
    subtitle = "Top 15 by normalized betweenness (bridging; not part of the composite)",
    x = NULL,
    y = "Normalized betweenness",
    fill = "Subject"
  )
ggsave(output_path("figures", "rq1_betweenness.png"),
       p1, width = 9, height = 6, dpi = 150)

top_15 <- head(results, 15)
p2 <- ggplot(results, aes(x = betweenness, y = downstream_reach)) +
  geom_point(alpha = 0.4, size = 1.5, colour = "grey50") +
  geom_point(data = top_15, colour = "#E45756", size = 2) +
  geom_text(data = top_15, aes(label = course), colour = "#E45756",
            size = 3, hjust = -0.15, check_overlap = TRUE) +
  labs(
    title = "Bridge position vs. downstream course reach",
    subtitle = "Red: top 15 by composite foundation rank",
    x = "Normalized betweenness",
    y = "Courses reachable downstream"
  )
ggsave(output_path("figures", "rq1_reach_vs_betweenness.png"),
       p2, width = 9, height = 6, dpi = 150)

degree_types <- c("Raw out-degree", "Option-weighted out-degree")
out_degree_long <- data.frame(
  type = factor(rep(degree_types, each = nrow(results)), levels = degree_types),
  value = c(results$out_degree, results$weighted_out_degree)
)
p3 <- ggplot(out_degree_long, aes(x = value)) +
  geom_histogram(binwidth = 1, fill = "#4C78A8", colour = "white") +
  facet_wrap(~ type, ncol = 1) +
  scale_y_continuous(transform = "log1p", breaks = c(0, 1, 10, 100, 1000)) +
  labs(
    title = "Distribution of prerequisite out-degree",
    subtitle = "Option-weighted: each edge counts its share of the dependent course's requirement",
    x = "Immediate downstream courses",
    y = "Number of courses (log scale)"
  )
ggsave(output_path("figures", "rq1_out_degree_distribution.png"),
       p3, width = 9, height = 7, dpi = 150)

figure_measures <- c(
  out_degree = "Raw out-degree",
  weighted_out_degree = "Option-weighted out-degree",
  pagerank_weighted = "PageRank (reversed, option-weighted)",
  harmonic_out_weighted = "Harmonic out (option-weighted)",
  downstream_reach = "Downstream reach",
  betweenness = "Betweenness"
)
top_by_measure <- do.call(rbind, lapply(names(figure_measures), function(m) {
  top <- head(results[order(-results[[m]]), ], 10)
  data.frame(
    measure = factor(figure_measures[[m]], levels = figure_measures),
    key = paste(m, top$course),
    degree_type = factor(rep(degree_types, each = 10), levels = degree_types),
    value = c(top$out_degree, top$weighted_out_degree)
  )
}))
top_by_measure$key <- factor(top_by_measure$key, levels = rev(unique(top_by_measure$key)))
p4 <- ggplot(top_by_measure, aes(x = value, y = key, fill = degree_type)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.75) +
  facet_wrap(~ measure, scales = "free_y", ncol = 2) +
  scale_y_discrete(labels = function(k) sub("^\\S+ ", "", k)) +
  scale_fill_manual(values = c("#BAB0AC", "#4C78A8")) +
  labs(
    title = "Top 10 courses by each measure: raw vs option-weighted out-degree",
    x = "Immediate downstream courses",
    y = NULL,
    fill = NULL
  ) +
  theme(legend.position = "top")
ggsave(output_path("figures", "rq1_top10_by_measure.png"),
       p4, width = 10, height = 11, dpi = 150)
