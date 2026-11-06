# COSC 421 - Research Question 1
# Preliminary Prerequisite Network Analysis

library(igraph)

# Load data from GitHub repository
courses <- read.csv(
  "Data/ubco_courses_nodes.csv",
  stringsAsFactors = FALSE
)

edges <- read.csv(
  "Data/ubco_prereq_edges.csv",
  stringsAsFactors = FALSE
)

# Keep prerequisite edges only
prereq_edges <- subset(
  edges,
  type == "prereq" &
    !is.na(source) &
    !is.na(target)
)

# Create node table
nodes <- data.frame(
  name = courses$course,
  subject = courses$subject,
  level = courses$level,
  title = courses$title
)

# Construct directed graph
g <- graph_from_data_frame(
  d = prereq_edges[, c("source", "target")],
  directed = TRUE,
  vertices = nodes
)

g <- simplify(
  g,
  remove.multiple = TRUE,
  remove.loops = TRUE
)

# Network summary
cat("Total courses:", vcount(g), "\n")
cat("Total prerequisite edges:", ecount(g), "\n")
cat("Network density:", edge_density(g), "\n")