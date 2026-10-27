import {
  GetSecretValueCommand,
  SecretsManagerClient
} from "@aws-sdk/client-secrets-manager";
import crypto from "node:crypto";
import { DateTime } from "luxon";
import mysql from "mysql2/promise";

const requiredEnvironmentVariables = ["EXPIRY_TABLE"];
const ACCESS_CODE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
const ACCESS_CODE_LENGTH = 6;

const secretsManager = new SecretsManagerClient({});
const generateAccessCode = () => {
  const randomBytes = crypto.randomBytes(ACCESS_CODE_LENGTH);
  return Array.from(
    randomBytes,
    (byte) => ACCESS_CODE_ALPHABET[byte % ACCESS_CODE_ALPHABET.length]
  ).join("");
};

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
  if (!process.env.DB_SECRET_ARN) {
    const { DB_USERNAME: username, DB_PASSWORD: password } = process.env;
    const missingCredentials = Object.entries({
      DB_USERNAME: username,
      DB_PASSWORD: password
    })
      .filter(([, value]) => !value)
      .map(([name]) => name);

    if (missingCredentials.length > 0) {
      throw new Error(
        `Missing database credentials: ${missingCredentials.join(", ")}`
      );
    }

    return { username, password };
  }

  const response = await secretsManager.send(
    new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN })
  );

  if (!response.SecretString) {
    throw new Error("The database secret does not contain SecretString");
  }

  const credentials = JSON.parse(response.SecretString);
  const requiredCredentials = ["username", "password"];
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

const getConnection = (credentials) => {
  const host = credentials.host || process.env.DB_HOST;
  const port = credentials.port || process.env.DB_PORT;
  const database = credentials.database || process.env.DB_NAME;
  const missingConnectionInfo = Object.entries({ host, port, database })
    .filter(([, value]) => value === undefined || value === "")
    .map(([name]) => name);

  if (missingConnectionInfo.length > 0) {
    throw new Error(
      `Database connection details are missing: ${missingConnectionInfo.join(", ")}`
    );
  }

  return mysql.createConnection({
    host,
    port: Number(port),
    database,
    user: credentials.username,
    password: credentials.password,
    timezone: "Z"
  });
};

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
        let timezoneAffectedRows = 0;

        for (const id of ids) {
          const [result] = await connection.execute(
            `UPDATE \`${process.env.EXPIRY_TABLE}\`
             SET expires_at = ?, code = ?
             WHERE id = ?`,
            [expiresAt, generateAccessCode(), id]
          );

          timezoneAffectedRows += result.affectedRows;
        }

        affectedRows += timezoneAffectedRows;
        updates.push({
          timezone,
          expiresAt: expiresAt.toISOString(),
          affectedRows: timezoneAffectedRows
        });
      }

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    }

    console.log(
      JSON.stringify({
        selectedRows: rows.length,
        affectedRows,
        updates
      })
    );

    return {
      selectedRows: rows.length,
      affectedRows,
      updates
    };
  } finally {
    await connection.end();
  }
};
