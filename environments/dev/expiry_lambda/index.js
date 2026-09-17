import {
  GetSecretValueCommand,
  SecretsManagerClient
} from "@aws-sdk/client-secrets-manager";
import { DateTime } from "luxon";
import mysql from "mysql2/promise";

const requiredEnvironmentVariables = ["DB_SECRET_ARN", "EXPIRY_TABLE"];

const secretsManager = new SecretsManagerClient({});

const getNextUtcMidnight = (timezone) => {
  const nextMidnight = DateTime.now()
    .setZone(timezone)
    .plus({ days: 1 })
    .startOf("day")
    .toUTC();

  if (!nextMidnight.isValid) {
    throw new Error(
      `Invalid IANA timezone '${timezone}': ${nextMidnight.invalidReason}`
    );
  }

  return nextMidnight.toJSDate();
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

export const handler = async () => {
  const missingVariables = requiredEnvironmentVariables.filter(
    (name) => !process.env[name]
  );

  if (missingVariables.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missingVariables.join(", ")}`
    );
  }

  if (!/^[A-Za-z0-9_]+$/.test(process.env.EXPIRY_TABLE)) {
    throw new Error("EXPIRY_TABLE contains an invalid identifier");
  }

  const credentials = await getDatabaseCredentials();
  const connection = await getConnection(credentials);

  try {
    const [rows] = await connection.execute(
      `SELECT ac.id, rc.timezone
       FROM \`${process.env.EXPIRY_TABLE}\` AS ac
       INNER JOIN recollection_centers AS rc
         ON rc.id = ac.recollection_center_id
       WHERE ac.expires_at IS NULL
          OR ac.expires_at <= UTC_TIMESTAMP()`
    );

    const rowsByTimezone = new Map();
    for (const row of rows) {
      if (!row.timezone) {
        console.warn(`Skipping access_code ${row.id}: timezone is missing`);
        continue;
      }

      const timezoneRows = rowsByTimezone.get(row.timezone) || [];
      timezoneRows.push(row.id);
      rowsByTimezone.set(row.timezone, timezoneRows);
    }

    let affectedRows = 0;
    const updates = [];

    await connection.beginTransaction();
    try {
      for (const [timezone, ids] of rowsByTimezone) {
        const expiresAt = getNextUtcMidnight(timezone);
        const placeholders = ids.map(() => "?").join(", ");
        const [result] = await connection.execute(
          `UPDATE \`${process.env.EXPIRY_TABLE}\`
           SET expires_at = ?
           WHERE id IN (${placeholders})`,
          [expiresAt, ...ids]
        );

        affectedRows += result.affectedRows;
        updates.push({
          timezone,
          expiresAt: expiresAt.toISOString(),
          affectedRows: result.affectedRows
        });
      }

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    }

    console.log(
      JSON.stringify({
        affectedRows,
        updates
      })
    );

    return {
      affectedRows,
      updates
    };
  } finally {
    await connection.end();
  }
};
