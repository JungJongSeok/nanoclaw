/**
 * macOS Keychain reader for Claude Code OAuth tokens.
 * Falls back gracefully on non-macOS or when Keychain is unavailable.
 */
import { execSync } from 'child_process';
import { logger } from './logger.js';

const KEYCHAIN_SERVICE = 'Claude Code-credentials';

interface ClaudeOAuthData {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

/**
 * Read the Claude Code OAuth access token from macOS Keychain.
 * Returns null if unavailable (non-macOS, no entry, keychain locked, etc).
 */
export function readKeychainOAuthToken(): string | null {
  if (process.platform !== 'darwin') return null;

  try {
    const raw = execSync(
      `security find-generic-password -s "${KEYCHAIN_SERVICE}" -w`,
      { encoding: 'utf-8', timeout: 5000, stdio: ['pipe', 'pipe', 'pipe'] },
    ).trim();

    const credentials = JSON.parse(raw);
    const oauth: ClaudeOAuthData | undefined = credentials.claudeAiOauth;

    if (!oauth?.accessToken) {
      logger.debug('Keychain: no claudeAiOauth.accessToken found');
      return null;
    }

    // Warn if token is expired but still return it — the API will reject
    // it and the CLI will eventually refresh it in the background.
    if (oauth.expiresAt && Date.now() > oauth.expiresAt) {
      logger.warn('Keychain: OAuth token is expired, CLI may need to refresh');
    }

    logger.debug('Keychain: OAuth token read successfully');
    return oauth.accessToken;
  } catch (err) {
    logger.debug({ err }, 'Keychain: failed to read OAuth token');
    return null;
  }
}
