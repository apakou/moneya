import { Networks } from '@stellar/stellar-sdk';

export type StellarNetworkName = 'TESTNET' | 'PUBLIC';

export interface StellarConfig {
  network: StellarNetworkName;
  networkPassphrase: string;
  /** Independent providers, tried in order (plan §3: failover). */
  horizonUrls: readonly string[];
  usdcCode: 'USDC';
  /** Circle's USDC issuer for this network. Required; there is deliberately no default. */
  usdcIssuer: string;
  /** Base fee per operation in stroops. */
  baseFeeStroops: number;
}

export function loadStellarConfig(env: NodeJS.ProcessEnv = process.env): StellarConfig {
  const network = env.STELLAR_NETWORK;
  if (network !== 'TESTNET' && network !== 'PUBLIC') {
    throw new Error('STELLAR_NETWORK must be TESTNET or PUBLIC');
  }
  const horizonUrls = (env.STELLAR_HORIZON_URLS ?? '')
    .split(',')
    .map((u) => u.trim())
    .filter(Boolean);
  if (horizonUrls.length === 0) {
    throw new Error('STELLAR_HORIZON_URLS must list at least one provider');
  }
  const usdcIssuer = env.STELLAR_USDC_ISSUER?.trim();
  if (!usdcIssuer) {
    throw new Error('STELLAR_USDC_ISSUER is required (verify it against Circle documentation)');
  }
  return {
    network,
    networkPassphrase: network === 'PUBLIC' ? Networks.PUBLIC : Networks.TESTNET,
    horizonUrls,
    usdcCode: 'USDC',
    usdcIssuer,
    baseFeeStroops: Number(env.STELLAR_BASE_FEE_STROOPS ?? 100),
  };
}
