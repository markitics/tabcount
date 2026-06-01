# Chart Axis Guidelines

TabCount charts should keep the y-axis anchored at zero and use a small number of round horizontal guide lines. The goal is to make the scale readable at a glance without over-gridding the tiny menu bar chart.

Guidelines:

- Always show `0`.
- Prefer either `0, interim, top` or `0, interim, interim, top`.
- Guide lines should be round numbers such as `5`, `10`, `20`, `25`, `40`, `50`, `100`, `200`, `500`, or `1,000`.
- It is acceptable for the actual maximum to sit above the top round guide line.
- If the actual maximum is more than about 10% away from the top round guide line, draw a light dashed max line and label it with the actual maximum.
- If the actual maximum is already close to the top round guide line, do not add the dashed max line.

Examples:

- Max up to about `14`: `0, 5, 10`
- Max `14-23`: `0, 10, 20`
- Max `24-33`: `0, 10, 20, 30`
- Max `34-43`: `0, 20, 40`
- Max `44-53`: `0, 25, 50`
- Max `54-68`: `0, 20, 40, 60`, with a dashed max line when the max is meaningfully above `60`
- Max `69-83`: `0, 40, 80`
- Max `84-110`: `0, 50, 100`
- Max `111-125`: `0, 40, 80, 120`
- Max `126-170`: `0, 50, 100, 150`
- Max around `171-240`: `0, 100, 200`
- Max around `1,272`: `0, 500, 1,000`, plus a dashed max line at `1,272`
