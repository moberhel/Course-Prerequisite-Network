# COSC 421 - Research Question 2
# Which prerequisite courses create the greatest access constraints for
# upper-level courses and specializations within UBCO Faculty of Science programs?
#
# Run from the repository root: Rscript RQ2/RQ2_network_analysis.R
# Outputs:
#   output/tables/rq2_constraint_results.csv
#   output/tables/rq2_removal_impact_detail.csv
#   output/tables/rq2_upper_level_constraints.csv
#   output/tables/rq2_subject_impact.csv
#   output/figures/rq2_*.png

library(igraph)
library(ggplot2)
source("R/00_load_network.R")

# ------------------------------------------------------------------
# 0. Configuration (edit here if the Science definition changes)
# ------------------------------------------------------------------
SCIENCE_SUBJECTS <- c("ASTR", "BIOC", "BIOL", "CHEM", "COSC", "DATA",
                      "EESC", "MATH", "PHYS", "STAT", "SCIE", "FWSC")
UPPER_LEVEL <- 300   # "upper-level" = 300- and 400-level courses
TOP_N       <- 15

# ------------------------------------------------------------------
# 1. Load data
# ------------------------------------------------------------------
course_data <- load_course_data()
courses <- course_data$nodes
edges <- course_data$edges

# Prerequisite edges only (co-requisites and "recommended" are not access barriers)
pre <- subset(edges, type == "prereq" & !is.na(source) & !is.na(target))
pre <- pre[!duplicated(pre[, c("source", "target")]), ]

ids <- courses$course
n   <- length(ids)
idx <- setNames(seq_len(n), ids)

is_sci      <- courses$subject %in% SCIENCE_SUBJECTS
is_upper    <- !is.na(courses$level) & courses$level >= UPPER_LEVEL
is_current  <- courses$in_current_calendar
is_sci_up   <- is_sci & is_upper & is_current   # the courses whose access we protect

cat("Science courses (current calendar):", sum(is_sci & is_current), "\n")
cat("Science upper-level courses:       ", sum(is_sci_up), "\n")

# ------------------------------------------------------------------
# 2. Build the directed prerequisite network (prerequisite -> course unlocked)
# ------------------------------------------------------------------
g <- build_prereq_graph(course_data)
cat("Network:", vcount(g), "nodes,", ecount(g), "prerequisite edges\n")
cat("Network is a DAG:", is_dag(g), "\n")

# ------------------------------------------------------------------
# 3. Betweenness centrality (gateway / bottleneck courses)
# ------------------------------------------------------------------
# (a) whole UBCO network - paths may pass through non-Science courses
bet_full_raw  <- betweenness(g, directed = TRUE, normalized = FALSE)
bet_full_norm <- bet_full_raw / ((n - 1) * (n - 2))

# (b) Science-only induced subgraph - bottlenecks inside Science programs
sci_names <- ids[is_sci & is_current]
g_sci     <- induced_subgraph(g, V(g)[name %in% sci_names])
bet_sci_raw  <- betweenness(g_sci, directed = TRUE, normalized = FALSE)
m <- vcount(g_sci)
bet_sci_norm <- bet_sci_raw / ((m - 1) * (m - 2))
cat("Science subgraph:", m, "nodes,", ecount(g_sci), "edges\n")

# ------------------------------------------------------------------
# 4. Downstream reach: Science upper-level courses reachable from each course
# ------------------------------------------------------------------
reach_sci_upper <- setNames(integer(n), ids)
for (v in ids) {
  d <- names(subcomponent(g, v, mode = "out"))
  d <- setdiff(d, v)
  reach_sci_upper[v] <- sum(is_sci_up[idx[d]])
}

# ------------------------------------------------------------------
# 5. Prerequisite logic (AND / OR) so that "removal" is realistic
#    A plain graph treats every edge as mandatory. Many UBCO prerequisites are
#    "one of A, B, C", so deleting one of them does not block the course.
#    We rebuild each course's requirement as a set of clauses:
#      - required edge (in every path)      -> need that course        (k = 1, 1 source)
#      - one_of group (same n_alternatives) -> need >= 1 of the group  (k = 1)
#      - two_of group                       -> need >= 2 of the group  (k = 2)
#      - edges that belong to only some whole-requirement alternatives
#        ("either (a) ... or (b) ...")      -> need >= 1 of them       (k = 1)
#    Standing, permission, credit-count and program restrictions are NOT modelled
#    (they cannot be expressed as edges), so blocking is a lower bound.
# ------------------------------------------------------------------
clauses <- vector("list", n); names(clauses) <- ids

for (t in unique(pre$target)) {
  e <- pre[pre$target == t, ]
  core <- e[e$in_every_path %in% TRUE, ]
  alt  <- e[!(e$in_every_path %in% TRUE), ]
  cl <- list()
  req <- core[core$requirement == "required", ]
  for (s in req$source) cl[[length(cl) + 1]] <- list(src = idx[[s]], k = 1L)
  for (rq in c("one_of", "two_of")) {
    sub <- core[core$requirement == rq, ]
    if (nrow(sub) == 0) next
    for (grp in split(sub, sub$n_alternatives)) {
      src <- idx[grp$source]
      cl[[length(cl) + 1]] <- list(src = unname(src),
                                   k = as.integer(min(if (rq == "two_of") 2 else 1, length(src))))
    }
  }
  if (nrow(alt) > 0)
    cl[[length(cl) + 1]] <- list(src = unname(idx[alt$source]), k = 1L)
  clauses[[t]] <- cl
}

has_clauses <- !vapply(clauses, is.null, logical(1))

satisfied <- function(t_i, avail) {
  for (cl in clauses[[t_i]]) if (sum(avail[cl$src]) < cl$k) return(FALSE)
  TRUE
}

# Fixpoint: which courses can eventually be taken, given a starting availability
# Retired codes are treated as always available (they cannot be "removed").
retired <- !is_current
base_start <- !has_clauses | retired

propagate <- function(avail, todo) {
  repeat {
    changed <- FALSE
    for (t_i in todo) {
      if (!avail[t_i] && satisfied(t_i, avail)) { avail[t_i] <- TRUE; changed <- TRUE }
    }
    if (!changed) break
  }
  avail
}

baseline <- propagate(base_start, which(has_clauses & !retired))
cat("Courses accessible in baseline:", sum(baseline & is_current), "of", sum(is_current), "\n")
cat("Science upper-level accessible in baseline:", sum(baseline & is_sci_up), "of", sum(is_sci_up), "\n")

# ------------------------------------------------------------------
# 6. Removal (what-if) analysis for every Science course that unlocks something
# ------------------------------------------------------------------
cand <- which(is_sci & is_current & degree(g, mode = "out")[ids] > 0)
detail <- list()
res <- data.frame(course = ids[cand], blocked_sci_upper = 0L, blocked_sci_upper_direct = 0L,
                  blocked_all = 0L, subjects_affected = 0L, stringsAsFactors = FALSE)

for (j in seq_along(cand)) {
  c_i <- cand[j]
  desc <- idx[setdiff(names(subcomponent(g, ids[c_i], mode = "out")), ids[c_i])]
  avail <- baseline
  avail[c(c_i, desc)] <- FALSE                 # reset everything that could be affected
  avail[c_i] <- FALSE
  todo <- intersect(desc, which(has_clauses & !retired))
  start <- avail
  start[desc[!has_clauses[desc]]] <- TRUE      # descendants without clauses stay available
  after <- propagate(start, todo)

  blocked <- baseline & !after & is_current
  blocked[c_i] <- FALSE
  b_up <- which(blocked & is_sci_up)
  direct_children <- idx[pre$target[pre$source == ids[c_i]]]

  res$blocked_sci_upper[j]        <- length(b_up)
  res$blocked_sci_upper_direct[j] <- sum(b_up %in% direct_children)
  res$blocked_all[j]              <- sum(blocked)
  res$subjects_affected[j]        <- length(unique(courses$subject[b_up]))

  if (length(b_up) > 0)
    detail[[j]] <- data.frame(removed_course = ids[c_i], blocked_course = ids[b_up],
                              blocked_subject = courses$subject[b_up],
                              blocked_level = courses$level[b_up],
                              direct_dependent = b_up %in% direct_children,
                              stringsAsFactors = FALSE)
}
detail <- do.call(rbind, detail)
write.csv(detail, output_path("tables", "rq2_removal_impact_detail.csv"), row.names = FALSE)

# ------------------------------------------------------------------
# 7. Combine metrics for all Science courses
# ------------------------------------------------------------------
sci_i <- which(is_sci & is_current)
out <- data.frame(
  course  = ids[sci_i],
  subject = courses$subject[sci_i],
  level   = courses$level[sci_i],
  title   = courses$title[sci_i],
  in_degree  = degree(g, mode = "in")[ids[sci_i]],
  out_degree = degree(g, mode = "out")[ids[sci_i]],
  betweenness_full      = bet_full_raw[ids[sci_i]],
  betweenness_full_norm = bet_full_norm[ids[sci_i]],
  betweenness_sci       = bet_sci_raw[ids[sci_i]],
  betweenness_sci_norm  = bet_sci_norm[ids[sci_i]],
  reach_sci_upper = reach_sci_upper[ids[sci_i]],
  stringsAsFactors = FALSE
)
out <- merge(out, res, by = "course", all.x = TRUE)
for (v in c("blocked_sci_upper", "blocked_sci_upper_direct", "blocked_all", "subjects_affected"))
  out[[v]][is.na(out[[v]])] <- 0L

# Composite constraint rank: mean of the ranks on three complementary measures
#   bottleneck position (betweenness), reach (downstream Science upper-level courses),
#   and hard blocking (courses that become inaccessible if it is removed)
out$constraint_rank_score <- rowMeans(cbind(
  rank(-out$betweenness_sci, ties.method = "average"),
  rank(-out$reach_sci_upper, ties.method = "average"),
  rank(-out$blocked_sci_upper, ties.method = "average")))
out <- out[order(out$constraint_rank_score, -out$blocked_sci_upper), ]
out$constraint_rank <- seq_len(nrow(out))
write.csv(out, output_path("tables", "rq2_constraint_results.csv"), row.names = FALSE)

cat("\nTop", TOP_N, "access-constraining Science courses:\n")
print(head(out[, c("constraint_rank", "course", "title", "betweenness_sci",
                   "reach_sci_upper", "blocked_sci_upper")], TOP_N), row.names = FALSE)

# ------------------------------------------------------------------
# 8. Upper-level view: how constrained is each 300/400-level Science course?
# ------------------------------------------------------------------
up_i <- which(is_sci_up)
spof <- table(factor(detail$blocked_course, levels = ids[up_i]))   # single points of failure

depth <- rep(NA_integer_, n); names(depth) <- ids
if (is_dag(g)) {
  topo <- as_ids(topo_sort(g, mode = "out"))
  depth[] <- 0L
  for (v in topo) {
    preds <- names(neighbors(g, v, mode = "in"))
    if (length(preds)) depth[v] <- max(depth[preds]) + 1L
  }
}
sci_anc <- vapply(ids[up_i], function(v) {
  a <- setdiff(names(subcomponent(g, v, mode = "in")), v)
  sum(is_sci[idx[a]])
}, numeric(1))

upper <- data.frame(
  course = ids[up_i], subject = courses$subject[up_i], level = courses$level[up_i],
  title = courses$title[up_i],
  science_prereq_ancestors = unname(sci_anc),
  longest_prereq_chain = unname(depth[ids[up_i]]),
  single_points_of_failure = as.integer(spof[ids[up_i]]),
  standing_required = courses$standing_required[up_i],
  stringsAsFactors = FALSE)
upper <- upper[order(-upper$single_points_of_failure, -upper$longest_prereq_chain), ]
write.csv(upper, output_path("tables", "rq2_upper_level_constraints.csv"), row.names = FALSE)

# Subject-to-subject impact (which areas are held up by which prerequisite subjects)
if (!is.null(detail) && nrow(detail) > 0) {
  detail$removed_subject <- courses$subject[idx[detail$removed_course]]
  subj <- as.data.frame(table(removed_subject = detail$removed_subject,
                              blocked_subject = detail$blocked_subject))
  subj <- subj[subj$Freq > 0, ]
  names(subj)[3] <- "course_pairs_blocked"
  write.csv(subj[order(-subj$course_pairs_blocked), ],
            output_path("tables", "rq2_subject_impact.csv"), row.names = FALSE)
}

# ------------------------------------------------------------------
# 9. Figures
# ------------------------------------------------------------------
theme_set(theme_minimal(base_size = 12))
top <- head(out, TOP_N)
top$label <- factor(top$course, levels = rev(top$course))

p1 <- ggplot(top, aes(x = label, y = blocked_sci_upper, fill = subject)) +
  geom_col() + coord_flip() +
  labs(title = "Science courses whose removal blocks the most upper-level courses",
       subtitle = "Top 15 by composite constraint rank; courses blocked given AND/OR prerequisite logic",
       x = NULL, y = "Science 300/400-level courses that become inaccessible", fill = "Subject")
ggsave(output_path("figures", "rq2_top_bottleneck_courses.png"),
       p1, width = 9, height = 6, dpi = 150)

lab <- head(out, 12)
p2 <- ggplot(out, aes(x = betweenness_sci_norm, y = blocked_sci_upper, colour = subject)) +
  geom_point(alpha = 0.7, size = 2) +
  geom_text(data = lab, aes(label = course), size = 3, vjust = -0.7, check_overlap = TRUE,
            show.legend = FALSE) +
  labs(title = "Bottleneck position vs. hard blocking (Science courses)",
       x = "Betweenness centrality (Science subgraph, normalised)",
       y = "Science upper-level courses blocked if removed", colour = "Subject")
ggsave(output_path("figures", "rq2_betweenness_vs_blocked.png"),
       p2, width = 9, height = 6, dpi = 150)

subj_tot <- aggregate(cbind(blocked_sci_upper, reach_sci_upper) ~ subject, data = out, FUN = max)
p3 <- ggplot(out[out$level <= 200, ], aes(x = reorder(subject, blocked_sci_upper, FUN = max),
                                          y = blocked_sci_upper)) +
  geom_boxplot(outlier.shape = NA, fill = "grey90") + geom_jitter(width = 0.15, alpha = 0.6) +
  coord_flip() +
  labs(title = "Entry-level (100/200) courses: blocking impact by subject",
       x = NULL, y = "Science upper-level courses blocked if removed")
ggsave(output_path("figures", "rq2_entry_level_blocking_by_subject.png"),
       p3, width = 8, height = 5, dpi = 150)

cat("\nDone. Generated tables are in output/tables/ and figures are in output/figures/\n")
