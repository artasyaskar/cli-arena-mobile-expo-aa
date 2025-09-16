import * as fs from 'fs';
import * as path from 'path';
import { OfflineSyncCLI } from '../../src/offline-sync/cli';
import { ActionQueue } from '../../src/offline-sync/action-queue';
describe('OfflineSyncCLI', () => {
  const testQueuePath = './test_cli_queue.json';
  const testConfigPath = './sync-config.json';
  let cli: OfflineSyncCLI;
  beforeEach(() => {
    // Clean up any existing test files
    [testQueuePath, testConfigPath].forEach(filePath => {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    });
    // Create a test config
    const testConfig = {
      queueFile: testQueuePath,
      conflictResolution: 'timestamp',
      maxRetries: 2,
      baseDelay: 500
    };
    fs.writeFileSync(testConfigPath, JSON.stringify(testConfig, null, 2));
    
    cli = new OfflineSyncCLI();
  });
  afterEach(() => {
    // Clean up test files
    [testQueuePath, testConfigPath].forEach(filePath => {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    });
  });
  describe('createAction', () => {
    it('should create CREATE action', () => {
      const actionId = cli.createAction('CREATE', 'users', {
        payload: JSON.stringify({
          id: 'test-user',
          name: 'Test User',
          email: 'test@example.com'
        })
      });
      expect(actionId).toBeTruthy();
      
      const actionQueue = new ActionQueue(testQueuePath);
      const actions = actionQueue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].type).toBe('CREATE');
      expect(actions[0].entity).toBe('users');
      expect(actions[0].payload.id).toBe('test-user');
    });
    it('should create UPDATE action', () => {
      const actionId = cli.createAction('UPDATE', 'users', {
        id: 'user-123',
        payload: JSON.stringify({
          name: 'Updated Name'
        }),
        conflictResolution: 'client-wins'
      });
      const actionQueue = new ActionQueue(testQueuePath);
      const actions = actionQueue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].type).toBe('UPDATE');
      expect(actions[0].id).toBe('user-123');
      expect(actions[0].conflict_resolution).toBe('client-wins');
    });
    it('should create DELETE action', () => {
      const actionId = cli.createAction('DELETE', 'posts', {
        id: 'post-456'
      });
      const actionQueue = new ActionQueue(testQueuePath);
      const actions = actionQueue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].type).toBe('DELETE');
      expect(actions[0].id).toBe('post-456');
    });
    it('should throw error for invalid CREATE action', () => {
      expect(() => {
        cli.createAction('CREATE', 'users', {});
      }).toThrow('CREATE action requires payload');
    });
    it('should throw error for invalid UPDATE action', () => {
      expect(() => {
        cli.createAction('UPDATE', 'users', { id: 'user-123' });
      }).toThrow('UPDATE action requires id and payload');
      expect(() => {
        cli.createAction('UPDATE', 'users', { 
          payload: JSON.stringify({ name: 'Test' }) 
        });
      }).toThrow('UPDATE action requires id and payload');
    });
    it('should throw error for invalid DELETE action', () => {
      expect(() => {
        cli.createAction('DELETE', 'users', {});
      }).toThrow('DELETE action requires id');
    });
  });
  describe('setupCommands', () => {
    it('should setup commander program with all commands', () => {
      const program = cli.setupCommands();
      
      expect(program.commands).toBeDefined();
      expect(program.commands.length).toBeGreaterThan(0);
      
      const commandNames = program.commands.map(cmd => cmd.name());
      expect(commandNames).toContain('create');
      expect(commandNames).toContain('update');
      expect(commandNames).toContain('delete');
      expect(commandNames).toContain('sync');
      expect(commandNames).toContain('status');
      expect(commandNames).toContain('clear');
    });
  });
  describe('showStatus', () => {
    it('should display queue status correctly', () => {
      // Add some test actions
      const actionQueue = new ActionQueue(testQueuePath);
      actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      const actionId2 = actionQueue.addAction({ type: 'UPDATE', entity: 'posts', id: 'post-1', payload: {} });
      actionQueue.updateActionStatus(actionId2, 'completed');
      
      // Mock console.log to capture output
      const consoleLogs: string[] = [];
      const originalLog = console.log;
      console.log = (msg: string) => consoleLogs.push(msg);
      
      try {
        cli.showStatus();
        
        expect(consoleLogs.some(log => log.includes('Total actions: 2'))).toBe(true);
        expect(consoleLogs.some(log => log.includes('Pending: 1'))).toBe(true);
        expect(consoleLogs.some(log => log.includes('Completed: 1'))).toBe(true);
      } finally {
        console.log = originalLog;
      }
    });
  });
  describe('clearQueue', () => {
    it('should clear all actions from queue', () => {
      // Add some actions first
      cli.createAction('CREATE', 'users', {
        payload: JSON.stringify({ id: 'test', name: 'Test' })
      });
      
      const actionQueue = new ActionQueue(testQueuePath);
      expect(actionQueue.getAllActions()).toHaveLength(1);
      
      cli.clearQueue();
      
      expect(actionQueue.getAllActions()).toHaveLength(0);
    });
  });
  describe('config loading', () => {
    it('should load configuration from file', () => {
      // Config file was created in beforeEach
      // We can verify the CLI was created without errors
      expect(cli).toBeDefined();
    });
    it('should use default config when file is missing', () => {
      // Remove config file
      if (fs.existsSync(testConfigPath)) {
        fs.unlinkSync(testConfigPath);
      }
      
      // Create new CLI without config file
      const cliWithoutConfig = new OfflineSyncCLI();
      
      expect(cliWithoutConfig).toBeDefined();
    });
  });
});
