import * as fs from 'fs';
import * as path from 'path';
import { ActionQueue, Action } from '../../src/offline-sync/action-queue';
describe('ActionQueue', () => {
  const testQueuePath = './test_queue.json';
  let actionQueue: ActionQueue;
  beforeEach(() => {
    // Clean up any existing test file
    if (fs.existsSync(testQueuePath)) {
      fs.unlinkSync(testQueuePath);
    }
    actionQueue = new ActionQueue(testQueuePath);
  });
  afterEach(() => {
    // Clean up test file
    if (fs.existsSync(testQueuePath)) {
      fs.unlinkSync(testQueuePath);
    }
  });
  describe('initialization', () => {
    it('should create queue file if it does not exist', () => {
      expect(fs.existsSync(testQueuePath)).toBe(true);
      const content = JSON.parse(fs.readFileSync(testQueuePath, 'utf8'));
      expect(content).toEqual([]);
    });
    it('should read existing queue file', () => {
      const existingActions = [{
        actionId: 'test-1',
        type: 'CREATE' as const,
        entity: 'users',
        payload: { name: 'Test' },
        timestamp: '2023-01-01T00:00:00Z',
        status: 'pending' as const,
        retryCount: 0
      }];
      fs.writeFileSync(testQueuePath, JSON.stringify(existingActions));
      
      const queue = new ActionQueue(testQueuePath);
      const actions = queue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].actionId).toBe('test-1');
    });
  });
  describe('addAction', () => {
    it('should add CREATE action to queue', () => {
      const actionId = actionQueue.addAction({
        type: 'CREATE',
        entity: 'users',
        payload: { name: 'John Doe', email: 'john@example.com' }
      });
      expect(actionId).toBeTruthy();
      const actions = actionQueue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].actionId).toBe(actionId);
      expect(actions[0].type).toBe('CREATE');
      expect(actions[0].entity).toBe('users');
      expect(actions[0].status).toBe('pending');
    });
    it('should add UPDATE action to queue', () => {
      const actionId = actionQueue.addAction({
        type: 'UPDATE',
        entity: 'users',
        id: 'user-123',
        payload: { name: 'Jane Doe' }
      });
      const actions = actionQueue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].type).toBe('UPDATE');
      expect(actions[0].id).toBe('user-123');
    });
    it('should add DELETE action to queue', () => {
      const actionId = actionQueue.addAction({
        type: 'DELETE',
        entity: 'users',
        id: 'user-123'
      });
      const actions = actionQueue.getAllActions();
      expect(actions).toHaveLength(1);
      expect(actions[0].type).toBe('DELETE');
      expect(actions[0].id).toBe('user-123');
    });
    it('should generate unique action IDs and timestamps', () => {
      const id1 = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      const id2 = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      
      expect(id1).not.toBe(id2);
      
      const actions = actionQueue.getAllActions();
      expect(actions[0].timestamp).not.toBe(actions[1].timestamp);
    });
  });
  describe('getPendingActions', () => {
    it('should return only pending actions', () => {
      const id1 = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      const id2 = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      
      actionQueue.updateActionStatus(id1, 'completed');
      
      const pending = actionQueue.getPendingActions();
      expect(pending).toHaveLength(1);
      expect(pending[0].actionId).toBe(id2);
    });
  });
  describe('updateActionStatus', () => {
    it('should update action status', () => {
      const actionId = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      
      actionQueue.updateActionStatus(actionId, 'syncing');
      
      const actions = actionQueue.getAllActions();
      expect(actions[0].status).toBe('syncing');
    });
    it('should update retry count', () => {
      const actionId = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      
      actionQueue.updateActionStatus(actionId, 'failed', 2);
      
      const actions = actionQueue.getAllActions();
      expect(actions[0].status).toBe('failed');
      expect(actions[0].retryCount).toBe(2);
    });
  });
  describe('removeAction', () => {
    it('should remove action from queue', () => {
      const actionId = actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      
      expect(actionQueue.getAllActions()).toHaveLength(1);
      
      actionQueue.removeAction(actionId);
      
      expect(actionQueue.getAllActions()).toHaveLength(0);
    });
  });
  describe('getActionsByEntity', () => {
    it('should return actions for specific entity', () => {
      actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      actionQueue.addAction({ type: 'CREATE', entity: 'posts', payload: {} });
      actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      
      const userActions = actionQueue.getActionsByEntity('users');
      expect(userActions).toHaveLength(2);
      userActions.forEach(action => {
        expect(action.entity).toBe('users');
      });
    });
  });
  describe('clear', () => {
    it('should clear all actions from queue', () => {
      actionQueue.addAction({ type: 'CREATE', entity: 'users', payload: {} });
      actionQueue.addAction({ type: 'CREATE', entity: 'posts', payload: {} });
      
      expect(actionQueue.getAllActions()).toHaveLength(2);
      
      actionQueue.clear();
      
      expect(actionQueue.getAllActions()).toHaveLength(0);
    });
  });
});
