# Weekly collection report Lambda

This Node.js Lambda queries MySQL and returns a PDF as an API Gateway-compatible
binary response. It does not add or change Terraform resources.

## Request

The handler accepts the fields directly or inside an API Gateway `body`:

```json
{
  "centerId": 12,
  "weekStart": "2026-09-21",
  "weekEnd": "2026-09-27"
}
```

Dates use UTC calendar days. Both dates are inclusive; the query uses an
exclusive upper bound at midnight after `weekEnd`.

## Configuration

Set `DB_SECRET_ARN` to the Secrets Manager secret already used by the expiry
Lambda. Set `REPORT_QUERY` to a parameterized MySQL query with three `?`
placeholders, in this order: center ID, UTC period start, and exclusive period
end. The query must return these aliases:

- `center_name`: collection center display name; return it even when there are
  no drop-offs in the selected period.
- `dropoff_number`: unique order number such as `BBX-2026-000123`, or `NULL`
  when the center has no matching drop-offs.
- `dropoff_date`: date/time of the drop-off.
- `gender_category`: `Unalabeled`, `Boy`, or `Girl`.
- `age_group`: `2-4`, `5-9`, or `10-14`.
- `box_count`: number of boxes represented by that drop-off/gender/age row.

Return one row per drop-off, gender, and age-group combination. The report
counts unique drop-off numbers, sums boxes, compares drop-offs and boxes by
gender, age group, and weekday, and combines classifications in the detail
list. The weekday comparison uses UTC dates. Use a `LEFT JOIN` so the center
name remains available for an empty week. The repository does not include the
application database schema, so the query must be matched to that schema when
the Lambda is wired into infrastructure.

## Output

The PDF includes BlessedBox branding, center and week, box/drop-off KPIs,
average daily drop-offs, and the highest-impact gender and age group by box
count. Vertical bar charts compare boxes by gender and age group, with each
group's share of its chart total and the underlying box/drop-off counts. The
charts include every group, including groups with zero impact. A weekday table
and a drop-off detail table (with separate gender and age columns) remain in
the report. It does not describe or infer box contents.
A visible disclaimer states that the report is unofficial, is for study
purposes, and does not represent official OCC records or positions. The handler
returns a base64-encoded `application/pdf` response.
