# UBCO prerequisite data (COSC 421 project)

## Running the analysis
Run every script from the repository root (R 4.x, package `igraph`).

All research-question scripts build the network the same way, through `R/00_load_network.R`:

```r
source("R/00_load_network.R")
course_data <- load_course_data()          # cleaned node + edge tables
g <- build_prereq_graph(course_data)       # prerequisite -> course graph (2,041 nodes, 3,363 edges)
g_all <- build_prereq_graph(course_data, c("prereq", "coreq", "recommended"))
write.csv(tbl, output_path("tables", "rq1_top10.csv"), row.names = FALSE)
ggsave(output_path("figures", "rq1_network.png"))
```

What the loader adds on top of the raw CSVs:
- True/False columns become logicals; `standing_required` is normalised (`3rd` -> `third`).
- `nodes$retired` (56 legacy codes) and `nodes$upper_level` (300+ and in the current calendar).
- `edges$share` = k / `n_alternatives` (a "two of 13" edge counts 2/13; `weight` is left unchanged).
- Checks that every edge endpoint exists and that there are no duplicate edges of the same type and no self-loops.

Generated tables and figures go in `output/tables/` and `output/figures/`.

Tests: `Rscript tests/test_load_network.R` (base R, no extra packages).

Source: UBC Okanagan Academic Calendar, Course Descriptions (https://okanagan.calendar.ubc.ca/course-descriptions). Collection date is not recorded here.

## Files
- `Data/ubco_courses_nodes.csv` - 2,041 courses across 71 subjects (node table). 1,985 are in the current calendar; 56 are retired/legacy codes kept because other courses still cite them (blank title, `in_current_calendar = False`). Undergraduate only apart from 2 NRSG 500-level codes.
- `Data/ubco_prereq_edges.csv` - 3,703 directed edges, `source` -> `target` (edge table, ready for igraph): 3,363 prereq, 241 coreq, 99 recommended.

## Nodes columns (`ubco_courses_nodes.csv`)
- `course`, `subject`, `subject_name`, `number`, `level`, `title`, `in_current_calendar`
- `prereq_text` / `coreq_text`: calendar wording, verbatim
- `standing_required`: second | third | fourth when a year standing is required
- `permission_required`: instructor/department permission
- `program_restricted`: limited to specific programs
- `credit_count_required`: needs "N credits of ..." (not expressible as edges)

## Edges columns (`ubco_prereq_edges.csv`)
- `type`: prereq | coreq | recommended
- `requirement`: required | one_of | two_of | recommended
- `n_alternatives`: number of courses in the same option group (blank for recommended)
- `weight`: 1 / `n_alternatives` (0 for recommended); for `two_of` this is still 1/n
- `hard_requirement`: true only for a lone, mandatory prerequisite
- `in_every_path`: false when the course has whole-requirement alternatives ("either (a)... or (b)...") and this edge is not in all of them
- `alt_paths_in_course`: number of whole-requirement alternatives for the target
- `min_grade`: minimum grade attached to the edge, when stated
- `source_subject`, `target_subject`, `cross_department`, `source_level`, `target_level`, `source_in_calendar`

Column meanings were inferred from the data, not from documentation of the generating script.

## Known limitations
- No `credits` column and no "credit for only one of" (exclusion) information.
- Requirements that name a range or a pool rather than specific courses cannot be edges. They appear only in `prereq_text`: POLI 429 ("POLI 310-329"), POLI 449 ("POLI 330-349"), POLI 469 ("POLI 350-369"), INDG 481 / INDG 495 ("INDG 200- or 300-level"), EDUC 100 (ENGL 009 placement alternative), plus all `credit_count_required`, `standing_required` and `permission_required` conditions.
- `standing_required` mixes `third` and `3rd` (`3rd` is used by FREN 344, MDST 499 and PHYS 336); normalise before grouping.
- 56 retired codes appear as nodes with no title or requirements; their own prerequisites are unknown.
- Hand-parsed from calendar text: spot-check before final analysis. Automated checks: no duplicate or self-loop edges, every edge endpoint exists as a node, and every course code cited in `prereq_text` / `coreq_text` has an edge (except the range cases above).
