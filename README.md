# UBCO prerequisite data (COSC 421 project)

Source: UBC Okanagan Academic Calendar, Course Descriptions (https://okanagan.calendar.ubc.ca/course-descriptions). The original Faculty of Science pull was collected Nov 1, 2026 (calendar showed 2026/27). The university-wide files below were added later; their exact collection date is not recorded here.

## Files

### Primary dataset (university-wide, 71 subjects)
- `Data/ubco_courses_nodes.csv` - 2,041 courses (node table). 1,985 are in the current calendar; 56 are retired/legacy codes kept because other courses still cite them (blank title, `in_current_calendar = False`). Undergraduate only apart from 2 NRSG 500-level codes.
- `Data/ubco_prereq_edges.csv` - 3,703 directed edges, `source` -> `target` (edge table, ready for igraph): 3,363 prereq, 241 coreq, 99 recommended.

### Residual Science files (older schema, rows not covered by the primary dataset)
- `Data/ubco_science_courses.csv` - 164 courses: 161 graduate (500+) Science courses, plus EESC 495, EESC 496 and SUST 400.
- `Data/ubco_science_prereq_edges.csv` - 9 edges whose target is one of those courses (7 BTEC, PHYS 535, SUST 400).

Everything else from the original Science files (387 courses, 803 edges) was replaced by the primary dataset, and `ubco_external_referenced_courses.csv` was deleted because the primary dataset now contains those courses as real nodes. The older files are still in git history (commit `a46768a`).

## Primary dataset columns

Nodes (`ubco_courses_nodes.csv`)
- `course`, `subject`, `subject_name`, `number`, `level`, `title`, `in_current_calendar`
- `prereq_text` / `coreq_text`: calendar wording, verbatim
- `standing_required`: second | third | fourth when a year standing is required
- `permission_required`: instructor/department permission
- `program_restricted`: limited to specific programs
- `credit_count_required`: needs "N credits of ..." (not expressible as edges)

Edges (`ubco_prereq_edges.csv`)
- `type`: prereq | coreq | recommended
- `requirement`: required | one_of | two_of | recommended
- `n_alternatives`: number of courses in the same option group (blank for recommended)
- `weight`: 1 / `n_alternatives` (0 for recommended); for `two_of` this is still 1/n
- `hard_requirement`: true only for a lone, mandatory prerequisite
- `in_every_path`: false when the course has whole-requirement alternatives ("either (a)... or (b)...") and this edge is not in all of them
- `alt_paths_in_course`: number of whole-requirement alternatives for the target
- `min_grade`: minimum grade attached to the edge, when stated
- `source_subject`, `target_subject`, `cross_department`, `source_level`, `target_level`, `source_in_calendar`

Column meanings above were inferred from the data, not from documentation of the generating script.

## Residual (older-schema) columns
`from_course`, `to_course`, `relation`, `path_id` / `n_paths` (whole-requirement alternatives), `group_id` / `n_groups` (AND-groups), `option_id` / `n_options_in_group` / `option_bundle_size` (OR-options), `is_mandatory`, `cross_department`, `from_in_dataset`. The courses file carries `prerequisite_expr` / `corequisite_expr` (`;` AND between groups, `,` OR within a group, `+` AND-bundle inside an option, `~` alternative whole paths), `other_requirements`, `recommended`, `credit_exclusions_or_equivalents`, `credits`.

## Known limitations
- The two schemas are different; load the primary dataset and the residual files separately, or convert before combining.
- The primary dataset has no `credits` column and no "credit for only one of" (exclusion) information. Both existed in the older Science courses file and were dropped for the courses that were replaced.
- Requirements that name a range or a pool rather than specific courses cannot be edges. They appear only in `prereq_text`: POLI 429 ("POLI 310-329"), POLI 449 ("POLI 330-349"), POLI 469 ("POLI 350-369"), INDG 481 / INDG 495 ("INDG 200- or 300-level"), EDUC 100 (ENGL 009 placement alternative), plus all `credit_count_required`, `standing_required` and `permission_required` conditions.
- `standing_required` mixes `third` and `3rd` (`3rd` is used by FREN 344, MDST 499 and PHYS 336); normalise before grouping.
- 56 retired codes appear as nodes with no title or requirements; their own prerequisites are unknown.
- Hand-parsed from calendar text: spot-check before final analysis. Automated checks run when the primary dataset was added: no duplicate or self-loop edges, every edge endpoint exists as a node, and every course code cited in `prereq_text` / `coreq_text` has an edge (except the range cases above).
