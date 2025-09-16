import * as fs from 'fs';
import * as path from 'path';
import { SyncEngine } from '../../src/offline-sync/sync-engine';
import { ActionQueue } from '../../src/offline-sync/action-queue';
describe('Integration Tests', () => {
  const testQueuePath = './test_integration_queue.json';
  const mockDbPath = './test_mock_db.json';
  let syncEngine: SyncEngine;
  let actionQueue: ActionQueue;
  const mockServerPath = path.resolve(__dirname, '../../tasks/cli-offline-user-sync/resources/mock_server.sh');
  beforeAll(() => {
    // Make sure mock server is executable
    if (fs.existsSync(mockServerPath)) {
      fs.chmodSync(mockServerPath, '755');
    }
  });
  beforeEach(() => {
    // Clean up any existing test files
    [testQueuePath, mockDbPath].forEach(filePath => {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    });
    // Initialize mock database with test data
    const initialDb = {
      users: [
        {
          id: 'user_1',
          name: 'Alice Wonderland',
          email: 'alice@example.com',
          version: 1,
          last_modified: '2023-01-01T10:00:00Z'
        }
      ],
      posts: [
        {
          id: 'post_1',
          userId: 'user_1',
          title: 'Hello World',
          content: 'My first post.',
          version: 1,
          last_modified: '2023-01-02T12:00:00Z'
        }
      ]
    };
    fs.writeFileSync(mockDbPath, JSON.stringify(initialDb, null, 2));
    // Set environment variable for mock server to use our test DB
    process.env.MOCK_DB_PATH = mockDbPath;
    syncEngine = new SyncEngine(testQueuePath, mockServerPath);
    actionQueue = syncEngine.getQueue();
    
    // Configure faster retries for testing
    syncEngine.getClient().setRetryConfig({
      maxRetries: 1,
      baseDelay: 100,
      maxDelay: 500,
      jitterFactor: 0
    });
  });
  afterEach(() => {
    // Clean up test files and environment
    [testQueuePath, mockDbPath].forEach(filePath => {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    });
    delete process.env.MOCK_DB_PATH;
  });
  describe('Complex conflict resolution scenarios', () => {
    it('should handle timestamp-based conflict resolution correctly', async () => {
      // Add an update with newer timestamp (should win)
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Alice Updated (Client Newer)'
        },
        conflict_resolution: 'timestamp'
      });
      // Override timestamp to be newer
      const actions = actionQueue.getAllActions();
      actions[0].timestamp = '2023-12-01T12:00:00Z';
      fs.writeFileSync(testQueuePath, JSON.stringify(actions, null, 2));
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(1);
      expect(report.conflicts).toBe(0);
    });
    it('should handle server-wins conflict resolution', async () => {
      // Add an update that will conflict and use server-wins strategy
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Alice Updated (Should be rejected)'
        },
        conflict_resolution: 'server-wins'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(0);
      expect(report.conflicts).toBe(1);
      expect(report.failed).toBe(1);
    });
    it('should handle create conflicts with different strategies', async () => {
      // Try to create user with existing ID using server-wins
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user_1',
          name: 'Duplicate Alice',
          email: 'duplicate@example.com'
        },
        conflict_resolution: 'server-wins'
      });
      // Try to create user with existing ID using client-wins
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user_1',
          name: 'Overwriting Alice',
          email: 'overwrite@example.com'
        },
        conflict_resolution: 'client-wins'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(2);
      expect(report.conflicts).toBe(1); // First action should conflict
      // Note: Second action might also conflict depending on mock server state persistence
    });
  });
  describe('Ordered action processing', () => {
    it('should process actions for same entity in chronological order', async () => {
      const userId = 'user_ordered_test';
      
      // Create user
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: userId,
          name: 'Initial Name',
          email: 'initial@example.com'
        }
      });
      // Update name
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: userId,
        payload: {
          name: 'Updated Name'
        },
        conflict_resolution: 'client-wins'
      });
      // Update email
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: userId,
        payload: {
          email: 'updated@example.com'
        },
        conflict_resolution: 'client-wins'
      });
      const report = await syncEngine.sync({ respectEntityOrder: true });
      
      expect(report.totalActions).toBe(3);
      // All actions should be processed in order
      expect(report.details).toHaveLength(3);
    });
    it('should handle mixed entity types correctly', async () => {
      // Create a user
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user_mixed_test',
          name: 'Mixed Test User',
          email: 'mixed@example.com'
        }
      });
      // Create a post for that user
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'posts',
        payload: {
          id: 'post_mixed_test',
          userId: 'user_mixed_test',
          title: 'Mixed Test Post',
          content: 'This is a test post.'
        }
      });
      // Update the user
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user_mixed_test',
        payload: {
          name: 'Mixed Test User Updated'
        },
        conflict_resolution: 'client-wins'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(3);
      // Actions should be grouped by entity+id, so user actions should be processed together
      expect(report.details).toHaveLength(3);
    });
  });
  describe('Idempotency and retry behavior', () => {
    it('should handle action idempotency with unique action IDs', async () => {
      // Add the same logical action twice (different action IDs)
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user_idempotent_test',
          name: 'Idempotent User',
          email: 'idempotent@example.com'
        }
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(1);
      
      // Check that the action was marked as completed
      const completedActions = actionQueue.getAllActions().filter(a => a.status === 'completed');
      expect(completedActions).toHaveLength(1);
    });
    it('should handle delete of already deleted records gracefully', async () => {
      // Try to delete a non-existent record
      actionQueue.addAction({
        type: 'DELETE',
        entity: 'users',
        id: 'non_existent_user',
        conflict_resolution: 'force-delete'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(1); // Should succeed as no-op
      expect(report.conflicts).toBe(0);
    });
  });
  describe('Batch processing', () => {
    it('should process large number of actions in batches', async () => {
      const numActions = 15;
      const batchSize = 5;
      
      // Add many CREATE actions
      for (let i = 0; i < numActions; i++) {
        actionQueue.addAction({
          type: 'CREATE',
          entity: 'users',
          payload: {
            id: `user_batch_${i}`,
            name: `Batch User ${i}`,
            email: `batch${i}@example.com`
          }
        });
      }
      const report = await syncEngine.sync({ batchSize });
      
      expect(report.totalActions).toBe(numActions);
      expect(report.successful).toBe(numActions);
      expect(report.failed).toBe(0);
      expect(report.details).toHaveLength(numActions);
    });
  });
  describe('Error recovery and data integrity', () => {
    it('should maintain queue integrity after partial sync failure', async () => {
      // Add a mix of valid and invalid actions
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'valid_user',
          name: 'Valid User',
          email: 'valid@example.com'
        }
      });
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'non_existent_user', // This will fail
        payload: {
          name: 'Should Fail'
        }
      });
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'posts',
        payload: {
          id: 'valid_post',
          userId: 'valid_user',
          title: 'Valid Post',
          content: 'This should work.'
        }
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(3);
      expect(report.successful).toBe(2); // CREATE actions should succeed
      expect(report.failed).toBe(1);     // UPDATE should fail
      
      // Check final action statuses
      const actions = actionQueue.getAllActions();
      const completed = actions.filter(a => a.status === 'completed');
      const failed = actions.filter(a => a.status === 'failed');
      
      expect(completed).toHaveLength(2);
      expect(failed).toHaveLength(1);
    });
  });
});
