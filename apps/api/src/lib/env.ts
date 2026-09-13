function getOptionalIntegerEnv(name: string, fallback: number) {
  const rawValue = process.env[name]?.trim();
  if (!rawValue) {
    return fallback;
  }

  const parsed = Number.parseInt(rawValue, 10);
  return Number.isInteger(parsed) ? parsed : fallback;
}

function getOptionalEnv(name: string) {
  const value = process.env[name]?.trim();
  return value ? value : null;
}

function getCommaSeparatedEnv(name: string) {
  const value = getOptionalEnv(name);
  if (!value) {
    return [];
  }

  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

const APP_ENVS = ["development", "staging", "production", "test"];

export type AppEnv = (typeof APP_ENVS)[number];
export type DataSource = "postgres" | "supabase";

function getAppEnv(): AppEnv {
  const rawValue = process.env.APP_ENV?.trim();
  if (!rawValue) {
    return "development";
  }

  if (APP_ENVS.includes(rawValue as AppEnv)) {
    return rawValue as AppEnv;
  }

  throw new Error(
    `Invalid APP_ENV "${rawValue}". Expected one of: ${APP_ENVS.join(", ")}.`,
  );
}

function getSupabaseConfig() {
  const supabaseUrl = getOptionalEnv("SUPABASE_URL");
  const supabaseSecretKey = getOptionalEnv("SUPABASE_SECRET_KEY");

  if (supabaseUrl && supabaseSecretKey) {
    return {
      supabaseUrl,
      supabaseSecretKey,
    };
  }

  if (!supabaseUrl && !supabaseSecretKey) {
    return {
      supabaseUrl: null,
      supabaseSecretKey: null,
    };
  }

  throw new Error(
    "SUPABASE_URL and SUPABASE_SECRET_KEY must be provided together.",
  );
}

export function resolveCorsAllowedOrigins(appEnv: AppEnv) {
  const configuredOrigins = getCommaSeparatedEnv("CORS_ALLOWED_ORIGINS");
  if (configuredOrigins.length > 0) {
    return configuredOrigins;
  }

  if (appEnv === "development") {
    return ["http://localhost:5173"];
  }

  throw new Error(
    "Provide CORS_ALLOWED_ORIGINS for non-development API environments.",
  );
}

const databaseUrl = getOptionalEnv("DATABASE_URL");
const supabaseConfig = getSupabaseConfig();
const appEnv = getAppEnv();
const dataSource: DataSource = databaseUrl ? "postgres" : "supabase";

if (!databaseUrl && !supabaseConfig.supabaseUrl) {
  throw new Error(
    "Provide DATABASE_URL for direct Postgres access or SUPABASE_URL and SUPABASE_SECRET_KEY for Supabase access.",
  );
}

/**
 * All four or none. A partial set cannot sign anything, and failing at the
 * point of sending would report it as a delivery problem rather than a
 * configuration one.
 */
function getApnsConfig() {
  const keyId = getOptionalEnv("APNS_KEY_ID");
  const teamId = getOptionalEnv("APNS_TEAM_ID");
  const bundleId = getOptionalEnv("APNS_BUNDLE_ID");
  // Railway keeps the newlines; a shell export often does not, and a key whose
  // line breaks became "\n" cannot be parsed.
  const privateKey = getOptionalEnv("APNS_PRIVATE_KEY")?.replace(/\\n/g, "\n");

  if (!keyId || !teamId || !bundleId || !privateKey) {
    return null;
  }

  return { keyId, teamId, bundleId, privateKey };
}

export const env = {
  appEnv,
  dataSource,
  databaseUrl,
  // Railway injects these on every deploy. Null anywhere else, which is how
  // /health reports a build it cannot identify rather than inventing one.
  commitSha: getOptionalEnv("RAILWAY_GIT_COMMIT_SHA"),
  branch: getOptionalEnv("RAILWAY_GIT_BRANCH"),
  apns: getApnsConfig(),
  host: process.env.HOST?.trim() || "0.0.0.0",
  port: getOptionalIntegerEnv("PORT", 3001),
  rawgApiKey: process.env.RAWG_API_KEY?.trim() || null,
  supabaseSecretKey: supabaseConfig.supabaseSecretKey,
  supabaseUrl: supabaseConfig.supabaseUrl,
};
