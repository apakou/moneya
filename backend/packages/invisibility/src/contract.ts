import { FORBIDDEN_KEY, FORBIDDEN_TERM } from './guard';

/**
 * Contract lint (plan §1.1, ticket INV-01): the PUBLIC API contract must be
 * fiat-only. Starting from every non-webhook operation's responses, follow
 * `$ref`s and report any property name or documentation/enum string that
 * reveals stablecoin or chain details.
 *
 * Webhook payloads come from third parties and are internal; they are out of scope.
 */
export interface ContractViolation {
  location: string;
  kind: 'key' | 'term';
  match: string;
}

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
type Obj = { [k: string]: Json };

const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v);

const HTTP_METHODS = ['get', 'put', 'post', 'delete', 'patch', 'options', 'head'];
const TEXT_KEYS = new Set(['summary', 'description', 'title', 'example', 'default', 'const']);

export function lintResponseContract(doc: unknown): ContractViolation[] {
  if (!isObj(doc)) throw new Error('OpenAPI document must be an object');
  const violations: ContractViolation[] = [];
  const schemas = (
    isObj(doc.components) && isObj(doc.components.schemas) ? doc.components.schemas : {}
  ) as Obj;
  const responses = (
    isObj(doc.components) && isObj(doc.components.responses) ? doc.components.responses : {}
  ) as Obj;
  const seen = new Set<string>();

  const checkText = (text: string, location: string): void => {
    const m = FORBIDDEN_TERM.exec(text);
    if (m) violations.push({ location, kind: 'term', match: m[0] });
  };

  const resolve = (ref: string): { name: string; node: Json | undefined } => {
    const [, group, name = ''] = /^#\/components\/(schemas|responses)\/(.+)$/.exec(ref) ?? [];
    const node =
      group === 'schemas' ? schemas[name] : group === 'responses' ? responses[name] : undefined;
    return { name: `${group}/${name}`, node };
  };

  const walk = (node: Json | undefined, location: string, propertyNames: boolean): void => {
    if (Array.isArray(node)) {
      node.forEach((item, i) => walk(item, `${location}[${i}]`, propertyNames));
      return;
    }
    if (!isObj(node)) return;
    if (typeof node.$ref === 'string') {
      const { name, node: target } = resolve(node.$ref);
      if (seen.has(name)) return;
      seen.add(name);
      if (target === undefined) {
        violations.push({
          location: `${location} -> ${node.$ref}`,
          kind: 'term',
          match: 'unresolved $ref',
        });
        return;
      }
      walk(target, name, true);
      return;
    }
    for (const [key, value] of Object.entries(node)) {
      const here = `${location}.${key}`;
      if (key === 'properties' && isObj(value)) {
        for (const [prop, schema] of Object.entries(value)) {
          if (FORBIDDEN_KEY.test(prop)) {
            violations.push({ location: `${here}.${prop}`, kind: 'key', match: prop });
          }
          walk(schema, `${here}.${prop}`, true);
        }
        continue;
      }
      if (key === 'enum' && Array.isArray(value)) {
        value.forEach((v) => typeof v === 'string' && checkText(v, here));
        continue;
      }
      if (TEXT_KEYS.has(key)) {
        if (typeof value === 'string') checkText(value, here);
        else if (isObj(value) || Array.isArray(value)) walk(value as Json, here, propertyNames);
        continue;
      }
      walk(value as Json, here, propertyNames);
    }
  };

  const paths = isObj(doc.paths) ? doc.paths : {};
  for (const [path, item] of Object.entries(paths)) {
    if (path.startsWith('/webhooks') || !isObj(item)) continue;
    for (const method of HTTP_METHODS) {
      const op = item[method];
      if (!isObj(op)) continue;
      const where = `${method.toUpperCase()} ${path}`;
      for (const field of ['summary', 'description'] as const) {
        const text = op[field];
        if (typeof text === 'string') checkText(text, `${where}.${field}`);
      }
      walk(op.responses, `${where}.responses`, true);
    }
  }
  return violations;
}
