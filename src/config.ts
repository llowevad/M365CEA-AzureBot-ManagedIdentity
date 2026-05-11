/**
 * Configuration loader — reads environment variables for bot identity and A2A endpoint.
 */

export interface AppConfig {
  /** User-Assigned Managed Identity client ID (also the bot App ID) */
  botAppId: string;
  /** Azure AD tenant ID */
  botTenantId: string;
  /** Base URL of the A2A orchestrator */
  a2aBaseUrl: string;
  /** Path to the A2A endpoint (e.g., /a2a/orchestrator) */
  a2aPath: string;
  /** HTTP port (default 3978) */
  port: number;
}

export function loadConfig(): AppConfig {
  // SDK reads MicrosoftAppId/MicrosoftAppTenantId internally for token validation.
  // Support both naming conventions for flexibility.
  const botAppId = process.env.MicrosoftAppId || requireEnv('BOT_APP_ID');
  const botTenantId = process.env.MicrosoftAppTenantId || requireEnv('BOT_TENANT_ID');
  const a2aBaseUrl = requireEnv('A2A_BASE_URL');
  const a2aPath = process.env.A2A_PATH || '/a2a/orchestrator';
  const port = parseInt(process.env.PORT || '3978', 10);

  return { botAppId, botTenantId, a2aBaseUrl, a2aPath, port };
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}
