// Jest setup file
// This file is run before each test suite
// Set test timeout
jest.setTimeout(30000);
// Mock console to reduce noise in tests unless explicitly testing console output
const originalConsole = console;
beforeEach(() => {
  // Preserve console methods but make them silent in tests
  global.console = {
    ...originalConsole,
    log: jest.fn(),
    info: jest.fn(),
    warn: jest.fn(),
    error: originalConsole.error // Keep errors visible
  };
});
afterEach(() => {
  // Restore original console
  global.console = originalConsole;
});
