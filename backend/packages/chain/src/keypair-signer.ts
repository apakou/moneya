import { Keypair } from '@stellar/stellar-sdk';
import type { Signer } from './types';

/**
 * In-memory signer for tests and testnet scripts ONLY. Production signing goes
 * through the KMS/HSM-backed signer service (ticket STL-03, decision D4).
 */
export class KeypairSigner implements Signer {
  constructor(private readonly keypair: Keypair) {}

  static random(): KeypairSigner {
    return new KeypairSigner(Keypair.random());
  }

  get publicKey(): string {
    return this.keypair.publicKey();
  }

  async sign(payload: Uint8Array): Promise<Uint8Array> {
    return new Uint8Array(this.keypair.sign(Buffer.from(payload)));
  }
}
