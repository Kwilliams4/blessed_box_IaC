import {
  GetSecretValueCommand,
  SecretsManagerClient
} from "@aws-sdk/client-secrets-manager";
import PDFDocument from "pdfkit";
import mysql from "mysql2/promise";

const requiredEnvironmentVariables = ["DB_SECRET_ARN", "REPORT_QUERY"];
const genderLabels = ["Unalabeled", "Boy", "Girl"];
const ageGroupLabels = ["2-4", "5-9", "10-14"];
const weekdayLabels = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday"
];
const secretsManager = new SecretsManagerClient({});
const colors = {
  ink: "#18352B",
  green: "#28765B",
  lightGreen: "#EAF3EE",
  orange: "#E79A42",
  muted: "#65736D",
  line: "#DCE4DF",
  white: "#FFFFFF"
};

const parseEvent = (event) => {
  if (event?.body === undefined) return event || {};
  if (typeof event.body !== "string") return event.body;

  try {
    return JSON.parse(event.body);
  } catch {
    throw new Error("Request body must be valid JSON");
  }
};

const parseDate = (value, name) => {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${name} must use the YYYY-MM-DD format`);
  }

  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== value
  ) {
    throw new Error(`${name} is not a valid calendar date`);
  }

  return parsed;
};

const getReportPeriod = ({ weekStart, weekEnd }) => {
  const start = parseDate(weekStart, "weekStart");
  const inclusiveEnd = parseDate(weekEnd, "weekEnd");
  if (inclusiveEnd < start) {
    throw new Error("weekEnd must be on or after weekStart");
  }

  const endExclusive = new Date(inclusiveEnd);
  endExclusive.setUTCDate(endExclusive.getUTCDate() + 1);

  return {
    start,
    endExclusive,
    label: `${weekStart} - ${weekEnd}`
  };
};

const getDatabaseCredentials = async () => {
  const response = await secretsManager.send(
    new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN })
  );

  if (!response.SecretString) {
    throw new Error("The database secret does not contain SecretString");
  }

  const credentials = JSON.parse(response.SecretString);
  const requiredCredentials = [
    "host",
    "port",
    "database",
    "username",
    "password"
  ];
  const missingCredentials = requiredCredentials.filter(
    (name) => credentials[name] === undefined || credentials[name] === ""
  );

  if (missingCredentials.length > 0) {
    throw new Error(
      `Database secret is missing: ${missingCredentials.join(", ")}`
    );
  }

  return credentials;
};

const getConnection = (credentials) =>
  mysql.createConnection({
    host: credentials.host,
    port: Number(credentials.port),
    database: credentials.database,
    user: credentials.username,
    password: credentials.password,
    timezone: "Z"
  });

const getReportData = async (connection, centerId, period) => {
  const [rows] = await connection.execute(process.env.REPORT_QUERY, [
    centerId,
    period.start,
    period.endExclusive
  ]);

  if (rows.length === 0) {
    throw new Error(`No collection center found for id '${centerId}'`);
  }

  const centerName = rows[0].center_name;
  if (typeof centerName !== "string" || !centerName.trim()) {
    throw new Error("REPORT_QUERY must return a non-empty center_name alias");
  }

  const dropoffs = rows
    .filter(
      (row) => row.dropoff_number !== null && row.dropoff_number !== undefined
    )
    .map((row) => {
      const boxCount = Number(row.box_count);
      if (!Number.isSafeInteger(boxCount) || boxCount < 0) {
        throw new Error("REPORT_QUERY returned an invalid box_count");
      }

      const gender = String(row.gender_category || "Unalabeled").trim();
      const normalizedGender = genderLabels.find(
        (label) => label.toLowerCase() === gender.toLowerCase()
      );
      if (!normalizedGender) {
        throw new Error(
          `REPORT_QUERY returned an unsupported gender_category '${gender}'`
        );
      }

      const ageGroup = String(row.age_group || "").trim();
      if (!ageGroupLabels.includes(ageGroup)) {
        throw new Error(
          `REPORT_QUERY returned an unsupported age_group '${ageGroup}'`
        );
      }

      const date =
        row.dropoff_date instanceof Date
          ? row.dropoff_date
          : new Date(row.dropoff_date);
      if (!row.dropoff_date || Number.isNaN(date.getTime())) {
        throw new Error("REPORT_QUERY returned an invalid dropoff_date");
      }

      return {
        id: String(row.dropoff_number),
        date,
        gender: normalizedGender,
        ageGroup,
        boxes: boxCount
      };
    });

  return { centerName: centerName.trim(), dropoffs };
};

const summarizeDropoffs = (dropoffs, daysInPeriod) => {
  const genders = new Map(
    genderLabels.map((label) => [
      label,
      {
        name: label,
        dropoffIds: new Set(),
        boxes: 0
      }
    ])
  );
  const ageGroups = new Map(
    ageGroupLabels.map((label) => [
      label,
      {
        name: label,
        dropoffIds: new Set(),
        boxes: 0
      }
    ])
  );
  const weekdays = new Map(
    weekdayLabels.map((label) => [
      label,
      {
        name: label,
        dropoffIds: new Set(),
        boxes: 0
      }
    ])
  );
  const dropoffIds = new Set();
  let totalBoxes = 0;

  for (const dropoff of dropoffs) {
    dropoffIds.add(dropoff.id);
    totalBoxes += dropoff.boxes;

    const gender = genders.get(dropoff.gender);
    gender.dropoffIds.add(dropoff.id);
    gender.boxes += dropoff.boxes;

    const ageGroup = ageGroups.get(dropoff.ageGroup);
    ageGroup.dropoffIds.add(dropoff.id);
    ageGroup.boxes += dropoff.boxes;

    const weekdayIndex = (dropoff.date.getUTCDay() + 6) % 7;
    const weekday = weekdays.get(weekdayLabels[weekdayIndex]);
    weekday.dropoffIds.add(dropoff.id);
    weekday.boxes += dropoff.boxes;
  }

  const toRows = (groups) =>
    [...groups.values()].map((group) => ({
      name: group.name,
      dropoffs: group.dropoffIds.size,
      boxes: group.boxes
    }));
  const weekdayRows = toRows(weekdays);
  const highestImpactGroup = (groups) => {
    const leader = groups.reduce((highest, group) =>
      group.boxes > highest.boxes ? group : highest
    );
    return leader.boxes > 0 ? leader : null;
  };

  return {
    totalBoxes,
    totalDropoffs: dropoffIds.size,
    averageDropoffsPerDay: dropoffIds.size / daysInPeriod,
    genders: toRows(genders),
    ageGroups: toRows(ageGroups),
    weekdays: weekdayRows,
    topGender: highestImpactGroup(toRows(genders)),
    topAgeGroup: highestImpactGroup(toRows(ageGroups))
  };
};

const getDropoffDetails = (dropoffs) => {
  const detailsById = new Map();
  for (const dropoff of dropoffs) {
    const detail = detailsById.get(dropoff.id) || {
      id: dropoff.id,
      date: dropoff.date,
      genders: new Set(),
      ageGroups: new Set(),
      boxes: 0
    };
    detail.genders.add(dropoff.gender);
    detail.ageGroups.add(dropoff.ageGroup);
    detail.boxes += dropoff.boxes;
    detailsById.set(dropoff.id, detail);
  }

  return [...detailsById.values()].map((detail) => ({
    ...detail,
    gender: [...detail.genders].join(", "),
    ageGroup: [...detail.ageGroups].join(", ")
  }));
};

const formatDropoffDate = (value) => {
  if (!value) return "-";
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "2-digit",
    year: "numeric",
    timeZone: "UTC"
  }).format(date);
};

const truncate = (document, value, width) => {
  let text = String(value);
  while (text.length > 1 && document.widthOfString(`${text}...`) > width) {
    text = text.slice(0, -1);
  }
  return text === String(value) ? text : `${text}...`;
};

const drawTableHeading = (document, title, columns, y) => {
  const left = document.page.margins.left;
  document
    .font("Helvetica-Bold")
    .fontSize(10)
    .fillColor(colors.ink)
    .text(title, left, y);
  const headerY = y + 22;
  document
    .rect(
      left,
      headerY,
      document.page.width - left - document.page.margins.right,
      22
    )
    .fill(colors.lightGreen);
  document.font("Helvetica-Bold").fontSize(8).fillColor(colors.green);
  for (const column of columns) {
    document.text(column.label, column.x, headerY + 7, {
      width: column.width,
      align: column.align || "left",
      lineBreak: false
    });
  }
  return headerY + 30;
};

const addPageIfNeeded = (document, y, requiredHeight) => {
  if (
    y + requiredHeight <=
    document.page.height - document.page.margins.bottom - 24
  ) {
    return y;
  }

  document.addPage();
  return document.page.margins.top;
};

const drawReportTable = (
  document,
  title,
  columns,
  rows,
  y,
  totalRow = null
) => {
  y = addPageIfNeeded(document, y, rows.length > 0 || totalRow ? 78 : 54);
  y = drawTableHeading(document, title, columns, y);

  if (rows.length === 0) {
    document
      .font("Helvetica")
      .fontSize(9)
      .fillColor(colors.muted)
      .text("No drop-offs recorded for this period.", columns[0].x, y + 4);
    y += 27;
  }

  for (const row of rows) {
    if (y + 23 > document.page.height - document.page.margins.bottom - 24) {
      document.addPage();
      y = drawTableHeading(
        document,
        `${title} (continued)`,
        columns,
        document.page.margins.top
      );
    }

    document.font("Helvetica").fontSize(9).fillColor(colors.ink);
    row.forEach((value, index) => {
      const column = columns[index];
      document.text(truncate(document, value, column.width), column.x, y, {
        width: column.width,
        align: column.align || "left",
        lineBreak: false
      });
    });
    y += 22;
    document
      .moveTo(document.page.margins.left, y - 8)
      .lineTo(document.page.width - document.page.margins.right, y - 8)
      .strokeColor(colors.line)
      .lineWidth(0.5)
      .stroke();
  }

  if (totalRow) {
    if (y + 27 > document.page.height - document.page.margins.bottom - 24) {
      document.addPage();
      y = drawTableHeading(
        document,
        `${title} (continued)`,
        columns,
        document.page.margins.top
      );
    }

    document
      .roundedRect(
        document.page.margins.left,
        y - 4,
        document.page.width -
          document.page.margins.left -
          document.page.margins.right,
        23,
        2
      )
      .fill(colors.lightGreen);
    document.font("Helvetica-Bold").fontSize(8.5).fillColor(colors.ink);
    totalRow.forEach((value, index) => {
      if (!value) return;
      const column = columns[index];
      document.text(truncate(document, value, column.width), column.x, y + 2, {
        width: column.width,
        align: column.align || "left",
        lineBreak: false
      });
    });
    y += 27;
  }

  return y + 15;
};

const drawComparisonChart = (document, title, subtitle, rows, x, y, width) => {
  const panelHeight = 184;
  const plotX = x + 34;
  const plotY = y + 48;
  const plotWidth = width - 46;
  const plotHeight = 78;
  const totalBoxes = rows.reduce((total, row) => total + row.boxes, 0);
  const slotWidth = plotWidth / rows.length;
  const barWidth = Math.min(30, slotWidth * 0.48);

  document.roundedRect(x, y, width, panelHeight, 4).fill("#F7F9F7");
  document
    .font("Helvetica-Bold")
    .fontSize(10)
    .fillColor(colors.ink)
    .text(title, x + 12, y + 11, { width: width - 24 });
  document
    .font("Helvetica")
    .fontSize(7)
    .fillColor(colors.muted)
    .text(subtitle, x + 12, y + 27);

  for (const percentage of [100, 50, 0]) {
    const gridY = plotY + plotHeight * (1 - percentage / 100);
    document
      .font("Helvetica")
      .fontSize(6.5)
      .fillColor(colors.muted)
      .text(`${percentage}%`, x + 3, gridY - 3, { width: 26, align: "right" });
    document
      .moveTo(plotX, gridY)
      .lineTo(plotX + plotWidth, gridY)
      .strokeColor(percentage === 0 ? colors.green : colors.line)
      .lineWidth(percentage === 0 ? 0.9 : 0.5)
      .stroke();
  }

  rows.forEach((row, index) => {
    const percentage = totalBoxes > 0 ? (row.boxes / totalBoxes) * 100 : 0;
    const barHeight = (plotHeight * percentage) / 100;
    const barX = plotX + index * slotWidth + (slotWidth - barWidth) / 2;
    const barY = plotY + plotHeight - barHeight;
    const labelCenter = plotX + index * slotWidth + slotWidth / 2;

    if (barHeight > 0) {
      document
        .rect(barX, barY, barWidth, barHeight)
        .fill(index === 0 ? colors.orange : colors.green);
    }
    document
      .font("Helvetica-Bold")
      .fontSize(7)
      .fillColor(colors.ink)
      .text(
        `${percentage.toFixed(1)}%`,
        labelCenter - slotWidth / 2,
        Math.max(plotY - 1, barY - 12),
        {
          width: slotWidth,
          align: "center",
          lineBreak: false
        }
      );
    document
      .font("Helvetica-Bold")
      .fontSize(7)
      .fillColor(colors.ink)
      .text(row.name, labelCenter - slotWidth / 2, plotY + plotHeight + 7, {
        width: slotWidth,
        align: "center",
        lineBreak: false
      });
    document
      .font("Helvetica")
      .fontSize(6.5)
      .fillColor(colors.muted)
      .text(
        `${row.boxes} boxes`,
        labelCenter - slotWidth / 2,
        plotY + plotHeight + 19,
        {
          width: slotWidth,
          align: "center",
          lineBreak: false
        }
      );
    document
      .font("Helvetica")
      .fontSize(6.5)
      .fillColor(colors.muted)
      .text(
        `${row.dropoffs} drop-offs`,
        labelCenter - slotWidth / 2,
        plotY + plotHeight + 30,
        {
          width: slotWidth,
          align: "center",
          lineBreak: false
        }
      );
  });

  return y + panelHeight;
};

export const generateReportPdf = async ({
  centerName,
  periodLabel,
  dropoffs,
  daysInPeriod = 7
}) => {
  if (!Array.isArray(dropoffs)) {
    throw new Error("dropoffs must be an array");
  }
  if (!Number.isSafeInteger(daysInPeriod) || daysInPeriod < 1) {
    throw new Error("daysInPeriod must be a positive integer");
  }

  const summary = summarizeDropoffs(dropoffs, daysInPeriod);
  const document = new PDFDocument({
    size: "A4",
    margins: { top: 48, bottom: 54, left: 48, right: 48 },
    bufferPages: true,
    info: {
      Title: `BlessedBox Weekly Collection Report - ${centerName}`,
      Author: "BlessedBox"
    }
  });
  const chunks = [];
  const pdfBuffer = new Promise((resolve, reject) => {
    document.on("data", (chunk) => chunks.push(chunk));
    document.on("end", () => resolve(Buffer.concat(chunks)));
    document.on("error", reject);
  });

  const pageWidth = document.page.width;
  const left = document.page.margins.left;
  const contentWidth = pageWidth - left - document.page.margins.right;

  document.rect(0, 0, pageWidth, 178).fill(colors.ink);
  document.rect(left, 42, 5, 48).fill(colors.orange);
  document
    .font("Helvetica-Bold")
    .fontSize(11)
    .fillColor(colors.orange)
    .text("BLESSEDBOX", left + 18, 43, { characterSpacing: 1.1 });
  document
    .font("Helvetica-Bold")
    .fontSize(25)
    .fillColor(colors.white)
    .text("Weekly collection report", left + 18, 65);
  document
    .font("Helvetica")
    .fontSize(12)
    .fillColor("#D8E6DF")
    .text(centerName, left + 18, 111, { width: contentWidth - 20 });
  document
    .font("Helvetica")
    .fontSize(9)
    .fillColor("#D8E6DF")
    .text(`Collection week  |  ${periodLabel}`, left + 18, 141);

  document.roundedRect(left, 187, contentWidth, 47, 3).fill("#FFF2E1");
  document.rect(left, 187, 4, 47).fill(colors.orange);
  document
    .font("Helvetica-Bold")
    .fontSize(8)
    .fillColor(colors.ink)
    .text("UNOFFICIAL - FOR STUDY PURPOSES ONLY", left + 13, 194);
  document
    .font("Helvetica")
    .fontSize(7.5)
    .fillColor(colors.ink)
    .text(
      "Based only on BlessedBox data. This is not an official OCC report and does not represent OCC's official records or position. Box contents are not recorded or inferred.",
      left + 13,
      207,
      {
        width: contentWidth - 25
      }
    );

  let y = 250;
  const gap = 8;
  const cardWidth = (contentWidth - gap * 4) / 5;
  const metrics = [
    ["BOXES COLLECTED", summary.totalBoxes.toLocaleString("en-US")],
    ["DROP-OFFS", summary.totalDropoffs.toLocaleString("en-US")],
    ["AVG. DROP-OFFS / DAY", summary.averageDropoffsPerDay.toFixed(1)],
    ["TOP GENDER BY BOXES", summary.topGender?.name || "-"],
    ["TOP AGE BY BOXES", summary.topAgeGroup?.name || "-"]
  ];

  metrics.forEach(([label, value], index) => {
    const x = left + index * (cardWidth + gap);
    document.roundedRect(x, y, cardWidth, 66, 4).fill(colors.lightGreen);
    document
      .font("Helvetica-Bold")
      .fontSize(index > 2 ? 7 : 7.5)
      .fillColor(colors.muted)
      .text(label, x + 10, y + 11, { width: cardWidth - 20 });
    document
      .font("Helvetica-Bold")
      .fontSize(index > 2 ? 13 : 17)
      .fillColor(colors.ink)
      .text(value, x + 10, y + 31, {
        width: cardWidth - 20,
        lineBreak: false
      });
  });

  y += 91;
  const breakdownColumns = [
    { label: "DAY", x: left + 10, width: contentWidth - 210 },
    {
      label: "DROP-OFFS",
      x: left + contentWidth - 190,
      width: 90,
      align: "right"
    },
    { label: "BOXES", x: left + contentWidth - 85, width: 75, align: "right" }
  ];
  y = drawReportTable(
    document,
    "Drop-offs by day of week",
    breakdownColumns,
    summary.weekdays.map((row) => [
      row.name,
      row.dropoffs.toLocaleString("en-US"),
      row.boxes.toLocaleString("en-US")
    ]),
    y
  );

  const chartWidth = (contentWidth - 18) / 2;
  y = addPageIfNeeded(document, y, 200);
  drawComparisonChart(
    document,
    "Boxes by gender",
    "Percent of all gender-classified boxes",
    summary.genders,
    left,
    y,
    chartWidth
  );
  drawComparisonChart(
    document,
    "Boxes by age group",
    "Percent of all age-classified boxes",
    summary.ageGroups,
    left + chartWidth + 18,
    y,
    chartWidth
  );
  y += 200;

  const detailColumns = [
    { label: "DROP-OFF #", x: left + 10, width: 116 },
    { label: "DATE", x: left + 140, width: 88 },
    { label: "GENDER", x: left + 238, width: 80 },
    { label: "AGE", x: left + 326, width: 68 },
    { label: "BOXES", x: left + contentWidth - 65, width: 55, align: "right" }
  ];
  const orderedDropoffs = getDropoffDetails(dropoffs).sort(
    (leftDropoff, rightDropoff) => leftDropoff.date - rightDropoff.date
  );
  y = drawReportTable(
    document,
    "Drop-off detail",
    detailColumns,
    orderedDropoffs.map((dropoff) => [
      dropoff.id,
      formatDropoffDate(dropoff.date),
      dropoff.gender,
      dropoff.ageGroup,
      dropoff.boxes.toLocaleString("en-US")
    ]),
    y,
    [
      `TOTAL (${summary.totalDropoffs} DROP-OFFS)`,
      "",
      "",
      "",
      summary.totalBoxes.toLocaleString("en-US")
    ]
  );

  const pageRange = document.bufferedPageRange();
  for (
    let page = pageRange.start;
    page < pageRange.start + pageRange.count;
    page += 1
  ) {
    document.switchToPage(page);
    document
      .font("Helvetica")
      .fontSize(8)
      .fillColor(colors.muted)
      .text(
        "BlessedBox  |  Collection impact report",
        left,
        document.page.height - 35,
        {
          lineBreak: false
        }
      );
    document.text(
      `${page + 1} / ${pageRange.count}`,
      left,
      document.page.height - 35,
      {
        width: contentWidth,
        align: "right",
        lineBreak: false
      }
    );
  }

  document.end();
  return pdfBuffer;
};

export const handler = async (event) => {
  const missingVariables = requiredEnvironmentVariables.filter(
    (name) => !process.env[name]
  );
  if (missingVariables.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missingVariables.join(", ")}`
    );
  }

  const input = parseEvent(event);
  if (!input?.centerId) throw new Error("centerId is required");
  const period = getReportPeriod(input);
  const credentials = await getDatabaseCredentials();
  const connection = await getConnection(credentials);

  try {
    const reportData = await getReportData(connection, input.centerId, period);
    const pdf = await generateReportPdf({
      ...reportData,
      periodLabel: period.label,
      daysInPeriod: Math.ceil((period.endExclusive - period.start) / 86400000)
    });

    return {
      statusCode: 200,
      isBase64Encoded: true,
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `inline; filename="blessedbox-weekly-${input.centerId}-${input.weekStart}.pdf"`
      },
      body: pdf.toString("base64")
    };
  } finally {
    await connection.end();
  }
};
