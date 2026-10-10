/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'node',
  rootDir: '.',
  testMatch: ['<rootDir>/apps/*/test/**/*.spec.ts', '<rootDir>/packages/*/test/**/*.spec.ts'],
  transform: { '^.+\\.ts$': ['ts-jest', { tsconfig: '<rootDir>/tsconfig.json' }] },
  moduleNameMapper: {
    '^@moneya/chain$': '<rootDir>/packages/chain/src/index.ts',
    '^@moneya/invisibility$': '<rootDir>/packages/invisibility/src/index.ts',
  },
  collectCoverageFrom: ['packages/*/src/**/*.ts', 'apps/*/src/**/*.ts', '!**/main.ts'],
};
