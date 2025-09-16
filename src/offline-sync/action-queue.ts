import * as fs from 'fs';
import * as path from 'path';
import { v4 as uuidv4 } from 'uuid';
export interface Action {
  actionId: string;
  type: 'CREATE' | 'UPDATE' | 'DELETE';
  entity: string;
  id?: string;
  payload?: any;
  timestamp: string;
  client_version?: number;
  conflict_resolution?: 'timestamp' | 'server-wins' | 'client-wins' | 'force-delete';
  retryCount?: number;
  status?: 'pending' | 'syncing' | 'completed' | 'failed';
}
export class ActionQueue {
  private queueFilePath: string;
  
  constructor(queueFilePath: string = './actions_queue.json') {
    this.queueFilePath = path.resolve(queueFilePath);
    this.initializeQueue();
  }
  private initializeQueue(): void {
    if (!fs.existsSync(this.queueFilePath)) {
      fs.writeFileSync(this.queueFilePath, JSON.stringify([]));
    }
  }
  private readQueue(): Action[] {
    try {
      const data = fs.readFileSync(this.queueFilePath, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      console.warn('Failed to read queue, initializing empty queue');
      return [];
    }
  }
  private writeQueue(actions: Action[]): void {
    fs.writeFileSync(this.queueFilePath, JSON.stringify(actions, null, 2));
  }
  addAction(action: Omit<Action, 'actionId' | 'timestamp' | 'status'>): string {
    const newAction: Action = {
      ...action,
      actionId: uuidv4(),
      timestamp: new Date().toISOString(),
      status: 'pending',
      retryCount: 0
    };
    const actions = this.readQueue();
    actions.push(newAction);
    this.writeQueue(actions);
    
    return newAction.actionId;
  }
  getPendingActions(): Action[] {
    return this.readQueue().filter(action => action.status === 'pending');
  }
  updateActionStatus(actionId: string, status: Action['status'], retryCount?: number): void {
    const actions = this.readQueue();
    const actionIndex = actions.findIndex(a => a.actionId === actionId);
    
    if (actionIndex !== -1) {
      actions[actionIndex].status = status;
      if (retryCount !== undefined) {
        actions[actionIndex].retryCount = retryCount;
      }
      this.writeQueue(actions);
    }
  }
  removeAction(actionId: string): void {
    const actions = this.readQueue();
    const filteredActions = actions.filter(a => a.actionId !== actionId);
    this.writeQueue(filteredActions);
  }
  getAllActions(): Action[] {
    return this.readQueue();
  }
  getActionsByEntity(entity: string): Action[] {
    return this.readQueue().filter(action => action.entity === entity);
  }
  clear(): void {
    this.writeQueue([]);
  }
}
