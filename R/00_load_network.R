# COSC 421 - Shared network loader
#
# Every research-question script should build the network through these
# functions so all RQs analyse exactly the same graph.
#
# Usage (run from the repository root):
#   source("R/00_load_network.R")
#   course_data <- load_course_data()
#   g <- build_prereq_graph(course_data)
#   write.csv(my_table, output_path("tables", "rq1_top10.csv"), row.names = FALSE)

library(igraph)

# Columns stored as "True"/"False" text in the CSVs.
NODE_FLAG_COLUMNS <- c(
  "in_current_calendar", "permission_required",
  "program_restricted", "credit_count_required"
)
EDGE_FLAG_COLUMNS <- c(
  "hard_requirement", "in_every_path", "cross_department", "source_in_calendar"
)

# Convert "True"/"False" text to logical, failing loudly on anything else.
as_flag <- function(x, column) {
  x <- trimws(as.character(x))
  bad <- !(x %in% c("True", "False"))
  if (any(bad)) {
    stop(sprintf(
      "Column '%s' has non True/False values: %s",
      column, paste(unique(x[bad]), collapse = ", ")
    ))
  }
  x == "True"
}

# Read and clean the node and edge tables.
#
# Returns list(nodes = data.frame, edges = data.frame) with:
#   * True/False columns converted to logical
#   * standing_required normalised ("3rd" -> "third"; blank -> NA)
#   * nodes$retired:     TRUE for the 56 legacy codes not in the current calendar
#   * nodes$upper_level: TRUE for current-calendar courses at the 300 level or above
#   * edges$share:       fraction of the option group this edge satisfies
#                        (k / n_alternatives, so "two of 13" edges count 2/13;
#                        the original `weight` column is kept unchanged)
load_course_data <- function(data_dir = "Data") {
  nodes_file <- file.path(data_dir, "ubco_courses_nodes.csv")
  edges_file <- file.path(data_dir, "ubco_prereq_edges.csv")
  for (f in c(nodes_file, edges_file)) {
    if (!file.exists(f)) {
      stop(sprintf("Missing data file '%s'. Run scripts from the repository root.", f))
    }
  }

  # Blank cells and R-style "NA" both mean missing, so files re-saved with
  # write.csv() load the same way as the originals.
  nodes <- read.csv(nodes_file, stringsAsFactors = FALSE, na.strings = c("", "NA"))
  edges <- read.csv(edges_file, stringsAsFactors = FALSE, na.strings = c("", "NA"))

  for (col in NODE_FLAG_COLUMNS) nodes[[col]] <- as_flag(nodes[[col]], col)
  for (col in EDGE_FLAG_COLUMNS) edges[[col]] <- as_flag(edges[[col]], col)

  nodes$standing_required[nodes$standing_required %in% "3rd"] <- "third"
  nodes$retired <- !nodes$in_current_calendar
  nodes$upper_level <- nodes$level >= 300 & !nodes$retired

  k_required <- ifelse(edges$requirement == "two_of", 2, 1)
  edges$share <- ifelse(
    edges$type == "recommended",
    0,
    k_required / edges$n_alternatives
  )

  list(nodes = nodes, edges = edges)
}

# Build the directed course network (edge direction: prerequisite -> course).
#
# edge_types: any of "prereq", "coreq", "recommended". Defaults to prerequisites
#             only, which is the network used in the progress report.
# All node and edge columns are attached as vertex/edge attributes.
build_prereq_graph <- function(course_data = load_course_data(),
                               edge_types = "prereq") {
  valid_types <- c("prereq", "coreq", "recommended")
  unknown <- setdiff(edge_types, valid_types)
  if (length(unknown) > 0) {
    stop(sprintf("Unknown edge type(s): %s", paste(unknown, collapse = ", ")))
  }

  nodes <- course_data$nodes
  edges <- course_data$edges[course_data$edges$type %in% edge_types, ]

  missing_endpoints <- setdiff(c(edges$source, edges$target), nodes$course)
  if (length(missing_endpoints) > 0) {
    stop(sprintf(
      "Edges reference unknown courses: %s",
      paste(head(missing_endpoints, 10), collapse = ", ")
    ))
  }

  # Columns are reordered so the course code / source / target come first,
  # as graph_from_data_frame() expects.
  vertex_df <- nodes[, c("course", setdiff(names(nodes), "course"))]
  edge_df <- edges[, c("source", "target", setdiff(names(edges), c("source", "target")))]

  g <- graph_from_data_frame(edge_df, directed = TRUE, vertices = vertex_df)

  # The same pair may legitimately appear under two types (7 pairs are both
  # "prereq" and "recommended"), so duplicates are checked within a type.
  if (anyDuplicated(edges[, c("source", "target", "type")]) > 0 ||
      any(which_loop(g))) {
    stop("Network contains duplicate edges or self-loops; check the edge table.")
  }

  g
}

# Path inside output/<kind>/, creating the folder if needed.
# kind: "tables" or "figures".
output_path <- function(kind = c("tables", "figures"), filename, root = "output") {
  kind <- match.arg(kind)
  dir <- file.path(root, kind)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, filename)
}
