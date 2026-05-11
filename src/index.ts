/**
 * Entry point — loads config and starts the Express server via the M365 Agents SDK.
 */

import { startServer } from '@microsoft/agents-hosting-express';
import { loadConfig } from './config';
import { createAgent } from './agent';

const config = loadConfig();
const agent = createAgent(config);

// Pass auth config explicitly — the SDK's env-based loader reads 'clientId'/'tenantId'
// (not 'MicrosoftAppId'/'MicrosoftAppTenantId'), so we provide it directly.
startServer(agent, {
  clientId: config.botAppId,
  tenantId: config.botTenantId,
});

console.log(`CEA relay agent configured for A2A endpoint: ${config.a2aBaseUrl}${config.a2aPath}`);
