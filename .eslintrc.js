// .eslintrc.js

/** @type {import('eslint').Linter.Config} */
module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  plugins: [
    '@typescript-eslint',
    'jest',
    'prettier',
  ],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:jest/recommended',
    'plugin:prettier/recommended' // ✅ includes "prettier" rules and sets prettier/prettier to error
  ],
  env: {
    node: true,
    jest: true,
    es2021: true,
  },
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
    project: './tsconfig.json', // ✅ needed for rules like `no-floating-promises`
    tsconfigRootDir: __dirname, // ✅ ensure ESLint resolves tsconfig properly
  },
  rules: {
    // Prettier will handle formatting
    'prettier/prettier': 'warn',

    // TypeScript
    '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/explicit-module-boundary-types': 'off',
    '@typescript-eslint/no-inferrable-types': 'off',

    // JS general
    'no-console': 'off',
    'no-unused-vars': 'off', // handled by TS plugin
    'eqeqeq': ['error', 'always'],
    'no-implicit-coercion': 'error',

    // Jest
    'jest/no-disabled-tests': 'warn',
    'jest/no-focused-tests': 'error',
    'jest/no-identical-title': 'error',
    'jest/prefer-to-have-length': 'warn',
    'jest/valid-expect': 'error',
  },
  settings: {
    jest: {
      version: require('jest/package.json').version,
    },
  },
  ignorePatterns: [
    'node_modules/',
    'dist/',
    'coverage/',
    '*.js',            // Ignore plain JS files
    '!*.config.js',     // But allow config JS files like .eslintrc.js, jest.config.js
    '*.d.ts',           // Ignore declaration files
  ],
};
