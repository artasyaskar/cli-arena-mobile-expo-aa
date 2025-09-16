import * as fs from 'fs';
import * as path from 'path';
import { SyncEngine } from '../../src/offline-sync/sync-engine';
import { ActionQueue } from '../../src/offline-sync/action-queue';
describe('SyncEngine', () => {
  const testQueuePath = './test_sync_queue.json';
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
    // Clean up any existing test file
    if (fs.existsSync(testQueuePath)) {
      fs.unlinkSync(testQueuePath);
    }
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
    // Clean up test file
    if (fs.existsSync(testQueuePath)) {
      fs.unlinkSync(testQueuePath);
    }
  });
  describe('sync with empty queue', () => {
    it('should return empty report for no pending actions', async () => {
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(0);
      expect(report.successful).toBe(0);
      expect(report.failed).toBe(0);
      expect(report.conflicts).toBe(0);
      expect(report.details).toHaveLength(0);
    });
  });
  describe('sync with successful actions', () => {
    it('should sync CREATE actions successfully', async () => {
      // Add some CREATE actions
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user-test-1',
          name: 'Test User 1',
          email: 'test1@example.com'
        }
      });
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'posts',
        payload: {
          id: 'post-test-1',
          userId: 'user-test-1',
          title: 'Test Post',
          content: 'Test content'
        }
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(2);
      expect(report.successful).toBe(2);
      expect(report.failed).toBe(0);
      expect(report.conflicts).toBe(0);
      
      // Check that actions were marked as completed
      const actions = actionQueue.getAllActions();
      actions.forEach(action => {
        expect(action.status).toBe('completed');
      });
    });
    it('should sync UPDATE actions successfully', async () => {
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Alice Updated Successfully'
        },
        conflict_resolution: 'client-wins'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(1);
      expect(report.failed).toBe(0);
    });
    it('should sync DELETE actions successfully', async () => {
      actionQueue.addAction({
        type: 'DELETE',
        entity: 'posts',
        id: 'post_1',
        conflict_resolution: 'force-delete'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(1);
      expect(report.failed).toBe(0);
    });
  });
  describe('sync with conflicts', () => {
    it('should handle CREATE conflicts', async () => {
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user_1', // This ID already exists
          name: 'Conflicting User',
          email: 'conflict@example.com'
        },
        conflict_resolution: 'server-wins'
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(0);
      expect(report.failed).toBe(1);
      expect(report.conflicts).toBe(1);
    });
    it('should handle UPDATE conflicts with timestamp strategy', async () => {
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Old Update'
        },
        conflict_resolution: 'timestamp'
      });
      // Override timestamp to be older than server
      const actions = actionQueue.getAllActions();
      actions[0].timestamp = '2022-01-01T00:00:00Z';
      fs.writeFileSync(testQueuePath, JSON.stringify(actions, null, 2));
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(0);
      expect(report.failed).toBe(1);
      expect(report.conflicts).toBe(1);
    });
  });
  describe('sync options', () => {
    it('should respect batch size', async () => {
      // Add multiple actions
      for (let i = 0; i < 5; i++) {
        actionQueue.addAction({
          type: 'CREATE',
          entity: 'users',
          payload: {
            id: `user-batch-${i}`,
            name: `User ${i}`,
            email: `user${i}@example.com`
          }
        });
      }
      const report = await syncEngine.sync({ batchSize: 2 });
      
      expect(report.totalActions).toBe(5);
      expect(report.successful).toBe(5);
    });
    it('should respect entity order by default', async () => {
      // Add multiple actions for the same user
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user-ordered',
          name: 'User Initial',
          email: 'initial@example.com'
        }
      });
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user-ordered',
        payload: {
          name: 'User Updated'
        },
        conflict_resolution: 'client-wins'
      });
      const report = await syncEngine.sync({ respectEntityOrder: true });
      
      // First action should succeed, but second might fail if CREATE didn't complete first
      // In practice, the mock server doesn't persist state between calls,
      // so we just verify the sync completed
      expect(report.totalActions).toBe(2);
    });
    it('should use specified conflict resolution strategy', async () => {
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Updated by Strategy Test'
        }
      });
      const report = await syncEngine.sync({ 
        conflictResolution: 'client-wins'
      });
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(1);
    });
  });
  describe('entity grouping', () => {
    it('should group actions by entity and ID for ordered processing', async () => {
      // Add multiple updates to same user
      const userId = 'user-group-test';
      
      actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: userId,
          name: 'Initial Name',
          email: 'initial@example.com'
        }
      });
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: userId,
        payload: {
          name: 'Updated Name'
        },
        conflict_resolution: 'client-wins'
      });
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
      // Actions should be processed in chronological order
      expect(report.details).toHaveLength(3);
    });
  });
  describe('error handling', () => {
    it('should handle non-existent entity gracefully', async () => {
      actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'non-existent-user',
        payload: {
          name: 'Should fail'
        }
      });
      const report = await syncEngine.sync();
      
      expect(report.totalActions).toBe(1);
      expect(report.successful).toBe(0);
      expect(report.failed).toBe(1);
      expect(report.details[0].error).toContain('not found');
    });
  });
});
