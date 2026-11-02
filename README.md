# UBCO Faculty of Science prerequisite data (COSC 421 project)

Source: UBC Okanagan Academic Calendar, Course Descriptions > Faculty of Science (https://okanagan.calendar.ubc.ca/course-descriptions/institution/501). Calendar page showed 2026/27 at collection (Nov 1, 2026).

## Files
- ubco_science_courses.csv - 551 courses, 16 subjects (390 undergrad, 161 grad 500+). One row per course (node table).
- ubco_science_prereq_edges.csv - 812 directed edges, from = prerequisite/corequisite, to = course unlocked (edge table, ready for igraph).
- ubco_external_referenced_courses.csv - 54 codes cited as prerequisites that aren't in the Science listing (other faculties, or retired Science codes).

## Edge columns
- relation: prerequisite | corequisite
- path_id / n_paths: whole-requirement alternatives (e.g. "either (a)... or (b)...")
- group_id / n_groups: AND-groups within a path ("one of A,B AND one of C,D" = 2 groups)
- option_id / n_options_in_group: OR-options within a group; option_bundle_size > 1 means that option needs several courses together
- is_mandatory: 1 if the edge has no alternative (single path, single option) - a "hard" prerequisite
- cross_department: 1 if from_subject != to_subject
- from_in_dataset: 0 if the source course is not in the Science listing

## Courses columns
prerequisite_expr / corequisite_expr use: ';' AND between groups, ',' OR within a group, '+' AND-bundle inside an OR option, '~' alternative whole paths.
other_requirements = non-course conditions (standing, permission, grades, high-school courses). recommended = "recommended" (not required) courses. credit_exclusions_or_equivalents = "credit for only one of" courses.

## Known limitations
- "Two of ..." / "6 credits of ..." / "third-year standing" can't be expressed as edges; they're listed in other_requirements (e.g. CHEM 462, CHEM 464, EESC 205/212/309/312/316).
- Only Faculty of Science subjects were collected; prerequisites from APSC/ENGR/GEOG/PSYO etc. appear as external nodes without their own prerequisites.
- Hand-parsed from calendar text: spot-check before final analysis.
