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

reach <- sapply(V(g)$name, function(course) {
  d <- names(subcomponent(g, course, mode = "out"))
  length(setdiff(d, course))
})

prereq_count <- sapply(V(g)$name, function(course) {
  d <- names(subcomponent(g, course, mode = "in"))
  length(setdiff(d, course))
})

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
  harmonic_in = harmonic_in[nodes$course],
  downstream_reach = as.integer(reach[nodes$course]),
  prerequisite_reach = as.integer(prereq_count[nodes$course]),
  pagerank = pagerank[nodes$course],
  pagerank_weighted = pagerank_weighted[nodes$course],
  current_calendar = nodes$in_current_calendar,
  retired = nodes$retired,
  stringsAsFactors = FALSE
)

results$composite_rank_score <- rowMeans(cbind(
  rank(-results$betweenness, ties.method = "average"),
  rank(-results$out_degree, ties.method = "average"),
  rank(-results$downstream_reach, ties.method = "average"),
  rank(-results$pagerank, ties.method = "average")
))
results <- results[order(results$composite_rank_score), ]
results$composite_rank <- seq_len(nrow(results))

write.csv(results,
          output_path("tables", "rq1_centrality_results.csv"),
          row.names = FALSE)

top_20 <- head(results, 20)
write.csv(top_20,
          output_path("tables", "rq1_top20_courses.csv"),
          row.names = FALSE)

cat("Network:", vcount(g), "courses,", ecount(g), "prerequisite edges\n")
cat("Network is a DAG:", is_dag(g), "\n")
cat("\nTop 20 central courses:\n")
print(top_20[, c("composite_rank", "course", "subject", "betweenness",
                 "out_degree", "downstream_reach", "pagerank")],
      row.names = FALSE)

theme_set(theme_minimal(base_size = 12))

top_15 <- head(results, 15)
top_15$label <- factor(top_15$course, levels = rev(top_15$course))
p1 <- ggplot(top_15, aes(x = label, y = betweenness, fill = subject)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Courses with the greatest betweenness centrality",
    subtitle = "Top 15 by composite centrality rank",
    x = NULL,
    y = "Normalized betweenness",
    fill = "Subject"
  )
ggsave(output_path("figures", "rq1_betweenness.png"),
       p1, width = 9, height = 6, dpi = 150)

p2 <- ggplot(results, aes(x = betweenness, y = downstream_reach,
                          colour = subject)) +
  geom_point(alpha = 0.55, size = 1.5) +
  geom_text(data = top_15, aes(label = course),
            size = 3, vjust = -0.7, check_overlap = TRUE,
            show.legend = FALSE) +
  labs(
    title = "Bridge position vs. downstream course reach",
    x = "Normalized betweenness",
    y = "Courses reachable downstream",
    colour = "Subject"
  )
ggsave(output_path("figures", "rq1_reach_vs_betweenness.png"),
       p2, width = 9, height = 6, dpi = 150)

p3 <- ggplot(results, aes(x = out_degree)) +
  geom_histogram(binwidth = 1, fill = "#4C78A8", colour = "white") +
  labs(
    title = "Distribution of prerequisite out-degree",
    x = "Number of immediate downstream courses",
    y = "Number of courses"
  )
ggsave(output_path("figures", "rq1_out_degree_distribution.png"),
       p3, width = 9, height = 5.5, dpi = 150)
