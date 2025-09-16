// Jest Global Setup File
// This file is run once per worker before all test suites.

// You can set up global mocks, environment variables, or other configurations here.

// Example: Mock a global function or module
// jest.mock('some-module', () => ({
//   someFunction: jest.fn(() => 'mocked value'),
// }));

// Example: Set up environment variables for tests
// process.env.TEST_API_KEY = 'test-api-key-value';

// beforeAll(() => {
//   // Runs once before all tests in this worker
//   console.log('Global Jest setup: beforeAll');
// });

// afterAll(() => {
//   // Runs once after all tests in this worker
//   console.log('Global Jest setup: afterAll');
// });

// If you need to clear mocks or perform other cleanup between tests,
// consider using `beforeEach` and `afterEach` within specific test files
// or in a setup file imported by test files.

// For now, this file can be kept simple.
// It's a good place for any future global test configurations.

// Silence console.log during tests unless explicitly needed for debugging
// You can enable/disable this as needed.
// let originalConsoleLog: any;
// let originalConsoleError: any;
// let originalConsoleWarn: any;

// beforeAll(() => {
//   originalConsoleLog = console.log;
//   originalConsoleError = console.error;
//   originalConsoleWarn = console.warn;
//   console.log = jest.fn();
//   console.error = jest.fn();
//   console.warn = jest.fn();
// });

// afterAll(() => {
//   console.log = originalConsoleLog;
//   console.error = originalConsoleError;
//   console.warn = originalConsoleWarn;
// });

// This ensures that test output is not cluttered with logs from the application code,
// unless a test is specifically designed to check console output.
// If a test needs to assert console output, it can spy on console.log directly.
// e.g., const consoleSpy = jest.spyOn(console, 'log');
//       expect(consoleSpy).toHaveBeenCalledWith('some message');
//       consoleSpy.mockRestore();

// For this project, let's keep console output enabled by default for now,
// as CLI interactions might be logged. We can refine this later.

console.log('Jest global setup file loaded.');
