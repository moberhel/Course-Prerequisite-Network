# Tests for R/00_load_network.R
# Run from the repository root:  Rscript tests/test_load_network.R
# Uses base R only (no testthat dependency). Exits non-zero if any test fails.

suppressPackageStartupMessages(source("R/00_load_network.R"))

failures <- 0

test <- function(name, expr) {
  ok <- tryCatch({
    force(expr)
    TRUE
  }, error = function(e) {
    message("    ", conditionMessage(e))
    FALSE
  })
  cat(sprintf("[%s] %s\n", if (ok) "PASS" else "FAIL", name))
  if (!ok) failures <<- failures + 1
}

expect_equal <- function(actual, expected) {
  if (!isTRUE(all.equal(actual, expected))) {
    stop(sprintf("expected %s, got %s",
                 paste(format(expected), collapse = " "),
                 paste(format(actual), collapse = " ")))
  }
}

expect_error <- function(expr, pattern) {
  msg <- tryCatch({
    force(expr)
    NULL
  }, error = function(e) conditionMessage(e))
  if (is.null(msg)) stop("expected an error, none was raised")
  if (!grepl(pattern, msg)) stop(sprintf("error '%s' did not match '%s'", msg, pattern))
}

d <- load_course_data()
g <- build_prereq_graph(d)

# --- Data loading ------------------------------------------------------------

test("node table has 2,041 courses", expect_equal(nrow(d$nodes), 2041L))

test("edge table has 3,703 edges (3,363 prereq, 241 coreq, 99 recommended)", {
  expect_equal(nrow(d$edges), 3703L)
  expect_equal(as.vector(table(d$edges$type)[c("prereq", "coreq", "recommended")]),
               c(3363L, 241L, 99L))
})

test("True/False columns are converted to logical", {
  for (col in NODE_FLAG_COLUMNS) stopifnot(is.logical(d$nodes[[col]]))
  for (col in EDGE_FLAG_COLUMNS) stopifnot(is.logical(d$edges[[col]]))
})

test("standing_required is normalised (no '3rd')", {
  stopifnot(!any(d$nodes$standing_required %in% "3rd"))
  expect_equal(sort(unique(na.omit(d$nodes$standing_required))),
               c("fourth", "second", "third"))
  expect_equal(sum(d$nodes$standing_required %in% "third"), 513L)
})

test("56 retired courses are flagged", expect_equal(sum(d$nodes$retired), 56L))

test("upper_level is 300+ and excludes retired courses", {
  stopifnot(all(d$nodes$level[d$nodes$upper_level] >= 300))
  stopifnot(!any(d$nodes$upper_level & d$nodes$retired))
  expect_equal(sum(d$nodes$upper_level),
               sum(d$nodes$level >= 300 & d$nodes$in_current_calendar))
})

test("share = k / n_alternatives (two_of counts double, recommended is 0)", {
  e <- d$edges
  two <- e$requirement == "two_of"
  expect_equal(e$share[two], 2 / e$n_alternatives[two])
  one <- e$requirement %in% c("required", "one_of")
  expect_equal(e$share[one], 1 / e$n_alternatives[one])
  stopifnot(all(e$share[e$type == "recommended"] == 0))
  stopifnot(all(e$share[e$type != "recommended"] > 0 & e$share[e$type != "recommended"] <= 1))
})

test("original weight column is unchanged", {
  raw <- read.csv("Data/ubco_prereq_edges.csv", stringsAsFactors = FALSE)
  expect_equal(d$edges$weight, raw$weight)
})

# --- Graph construction ------------------------------------------------------

test("default graph matches progress report: 2,041 nodes, 3,363 edges", {
  expect_equal(vcount(g), 2041L)
  expect_equal(ecount(g), 3363L)
  stopifnot(all(E(g)$type == "prereq"))
})

test("graph is directed and acyclic (prerequisite -> course)", {
  stopifnot(is_directed(g), is_dag(g))
})

test("edge direction is prerequisite -> course (COSC 344 -> COSC 444)", {
  stopifnot(are_adjacent(g, "COSC 344", "COSC 444"))
  stopifnot(!are_adjacent(g, "COSC 444", "COSC 344"))
})

test("matches the original RQ1 script's graph (same edge set)", {
  raw <- read.csv("Data/ubco_prereq_edges.csv", stringsAsFactors = FALSE)
  raw <- raw[raw$type == "prereq", ]
  old <- simplify(graph_from_data_frame(raw[, c("source", "target")],
                                        vertices = d$nodes$course))
  expect_equal(sort(as_ids(E(old))), sort(as_ids(E(g))))
})

test("vertex and edge attributes are attached", {
  for (a in c("subject", "level", "title", "retired", "upper_level", "standing_required"))
    stopifnot(a %in% vertex_attr_names(g))
  for (a in c("requirement", "n_alternatives", "weight", "share",
              "cross_department", "in_every_path", "min_grade"))
    stopifnot(a %in% edge_attr_names(g))
  expect_equal(V(g)["MATH 200"]$subject, "MATH")
  expect_equal(E(g)[.from("COSC 344") & .to("COSC 444")]$requirement, "required")
})

test("all edge types can be combined (7 prereq/recommended pairs allowed)", {
  ga <- build_prereq_graph(d, c("prereq", "coreq", "recommended"))
  expect_equal(ecount(ga), 3703L)
  expect_equal(sum(which_multiple(ga)), 7L)
})

test("unknown edge type is rejected",
     expect_error(build_prereq_graph(d, "prerequisite"), "Unknown edge type"))

# --- Validation on bad input -------------------------------------------------

make_bad_data <- function(mutate) {
  dir <- tempfile("bad_data_")
  dir.create(dir)
  file.copy("Data/ubco_courses_nodes.csv", dir)
  edges <- read.csv("Data/ubco_prereq_edges.csv", stringsAsFactors = FALSE)
  write.csv(mutate(edges), file.path(dir, "ubco_prereq_edges.csv"), row.names = FALSE)
  dir
}

test("edge to an unknown course is rejected", {
  dir <- make_bad_data(function(e) { e$target[1] <- "FAKE 999"; e })
  expect_error(build_prereq_graph(load_course_data(dir)), "unknown courses: FAKE 999")
})

test("duplicate edge of the same type is rejected", {
  dir <- make_bad_data(function(e) rbind(e, e[1, ]))
  expect_error(build_prereq_graph(load_course_data(dir)), "duplicate edges")
})

test("self-loop is rejected", {
  dir <- make_bad_data(function(e) { e$target[1] <- e$source[1]; e })
  expect_error(build_prereq_graph(load_course_data(dir)), "self-loops")
})

test("malformed True/False value is rejected", {
  dir <- make_bad_data(function(e) { e$hard_requirement[1] <- "yes"; e })
  expect_error(load_course_data(dir), "hard_requirement")
})

test("missing data directory gives a helpful error",
     expect_error(load_course_data("no_such_dir"), "repository root"))

# --- Output helper -----------------------------------------------------------

test("output_path creates folders and returns the file path", {
  root <- tempfile("out_")
  p <- output_path("figures", "x.png", root = root)
  expect_equal(p, file.path(root, "figures", "x.png"))
  stopifnot(dir.exists(file.path(root, "figures")))
  expect_error(output_path("plots", "x.png", root = root), "should be one of")
})

cat(sprintf("\n%d failed\n", failures))
if (failures > 0) quit(status = 1)
