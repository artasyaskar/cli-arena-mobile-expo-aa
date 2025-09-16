import * as path from 'path';
import * as fs from 'fs';
import { SupabaseClient } from '../../src/offline-sync/supabase-client';
import { Action } from '../../src/offline-sync/action-queue';
describe('SupabaseClient', () => {
  let client: SupabaseClient;
  const mockServerPath = path.resolve(__dirname, '../../tasks/cli-offline-user-sync/resources/mock_server.sh');
  beforeAll(() => {
    // Make sure mock server is executable
    if (fs.existsSync(mockServerPath)) {
      fs.chmodSync(mockServerPath, '755');
    }
  });
  beforeEach(() => {
    client = new SupabaseClient(mockServerPath);
    // Set faster retry config for testing
    client.setRetryConfig({
      maxRetries: 1,
      baseDelay: 100,
      maxDelay: 500,
      jitterFactor: 0
    });
  });
  describe('CREATE operations', () => {
    it('should successfully create a new record', async () => {
      const action: Action = {
        actionId: 'test-create-1',
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user-new-1',
          name: 'New User',
          email: 'newuser@example.com'
        },
        timestamp: new Date().toISOString(),
        status: 'pending'
      };
      const result = await client.syncAction(action);
      
      expect(result.success).toBe(true);
      expect(result.actionId).toBe(action.actionId);
      expect(result.operation).toBe('create');
      expect(result.data).toBeDefined();
    });
    it('should handle create conflicts with server-wins strategy', async () => {
      const action: Action = {
        actionId: 'test-create-conflict',
        type: 'CREATE',
        entity: 'users',
        payload: {
          id: 'user_1', // This ID already exists in mock DB
          name: 'Conflicting User',
          email: 'conflict@example.com'
        },
        timestamp: new Date().toISOString(),
        status: 'pending',
        conflict_resolution: 'server-wins'
      };
      const result = await client.syncAction(action);
      
      expect(result.success).toBe(false);
      expect(result.conflict).toBe(true);
      expect(result.error).toContain('already exists');
    });
  });
  describe('UPDATE operations', () => {
    it('should successfully update a record with client-wins strategy', async () => {
      const action: Action = {
        actionId: 'test-update-1',
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Updated Alice',
          email: 'alice.updated@example.com'
        },
        timestamp: '2023-12-01T12:00:00Z', // Future timestamp
        status: 'pending',
        conflict_resolution: 'client-wins'
      };
      const result = await client.syncAction(action);
      
      expect(result.success).toBe(true);
      expect(result.operation).toBe('update');
    });
    it('should handle update conflicts with timestamp strategy', async () => {
      const action: Action = {
        actionId: 'test-update-conflict',
        type: 'UPDATE',
        entity: 'users',
        id: 'user_1',
        payload: {
          name: 'Old Update'
        },
        timestamp: '2022-01-01T12:00:00Z', // Old timestamp
        status: 'pending',
        conflict_resolution: 'timestamp'
      };
      const result = await client.syncAction(action);
      
      expect(result.success).toBe(false);
      expect(result.conflict).toBe(true);
      expect(result.error).toContain('newer');
    });
  });
  describe('DELETE operations', () => {
    it('should successfully delete a record', async () => {
      const action: Action = {
        actionId: 'test-delete-1',
        type: 'DELETE',
        entity: 'posts',
        id: 'post_1',
        timestamp: new Date().toISOString(),
        status: 'pending',
        conflict_resolution: 'force-delete'
      };
      const result = await client.syncAction(action);
      
      expect(result.success).toBe(true);
      expect(result.operation).toBe('delete');
    });
    it('should handle delete of non-existent record gracefully', async () => {
      const action: Action = {
        actionId: 'test-delete-nonexistent',
        type: 'DELETE',
        entity: 'users',
        id: 'non-existent-user',
        timestamp: new Date().toISOString(),
        status: 'pending'
      };
      const result = await client.syncAction(action);
      
      expect(result.success).toBe(true);
      expect(result.operation).toBe('delete_noop');
    });
  });
  describe('error handling and retries', () => {
    it('should handle network failures with retries', async () => {
      // Use non-existent script to simulate network failure
      const failingClient = new SupabaseClient('/non/existent/script.sh');
      failingClient.setRetryConfig({ maxRetries: 2, baseDelay: 50, maxDelay: 100, jitterFactor: 0 });
      const action: Action = {
        actionId: 'test-retry',
        type: 'CREATE',
        entity: 'users',
        payload: { id: 'test', name: 'Test' },
        timestamp: new Date().toISOString(),
        status: 'pending'
      };
      const startTime = Date.now();
      const result = await failingClient.syncAction(action);
      const duration = Date.now() - startTime;
      
      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      // Should have taken some time due to retries
      expect(duration).toBeGreaterThan(100);
    }, 10000);
    it('should respect retry configuration', () => {
      const newConfig = {
        maxRetries: 5,
        baseDelay: 2000,
        maxDelay: 15000,
        jitterFactor: 0.2
      };
      
      client.setRetryConfig(newConfig);
      
      // We can't easily test the internal config, but we can verify the method doesn't throw
      expect(() => client.setRetryConfig(newConfig)).not.toThrow();
    });
  });
});
