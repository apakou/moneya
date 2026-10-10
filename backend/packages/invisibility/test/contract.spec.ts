import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { lintResponseContract } from '@moneya/invisibility';

const SPEC = join(__dirname, '../../../../docs/backend/openapi.yaml');

describe('INV-01: public API contract is fiat-only', () => {
  it('docs/backend/openapi.yaml exposes no stablecoin or chain details in responses', () => {
    const doc = parse(readFileSync(SPEC, 'utf8'));
    expect(lintResponseContract(doc)).toEqual([]);
  });

  it('detects a leaky response schema (the lint itself works)', () => {
    const doc = {
      paths: {
        '/v1/x': {
          get: {
            summary: 'Get x',
            responses: {
              '200': {
                content: { 'application/json': { schema: { $ref: '#/components/schemas/X' } } },
              },
            },
          },
        },
        '/webhooks/provider': {
          post: { responses: { '200': { description: 'Accepted via USDC webhook' } } },
        },
      },
      components: {
        schemas: {
          X: {
            type: 'object',
            properties: {
              amount_usdc: { type: 'string' },
              note: { type: 'string', description: 'Paid on Stellar' },
              inner: { $ref: '#/components/schemas/Y' },
            },
          },
          Y: { type: 'object', properties: { chain: { type: 'string', enum: ['SOLANA'] } } },
        },
      },
    };
    const found = lintResponseContract(doc)
      .map((v) => `${v.kind}:${v.match}`)
      .sort();
    expect(found).toEqual(['key:amount_usdc', 'key:chain', 'term:SOLANA', 'term:Stellar'].sort());
  });

  it('reports unresolved references instead of silently passing', () => {
    const doc = {
      paths: {
        '/v1/y': { get: { responses: { '200': { $ref: '#/components/responses/Missing' } } } },
      },
    };
    expect(lintResponseContract(doc).map((v) => v.match)).toContain('unresolved $ref');
  });
});
