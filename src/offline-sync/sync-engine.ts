import { ActionQueue, Action } from './action-queue';
import { SupabaseClient, SyncResult } from './supabase-client';
export interface SyncOptions {
  conflictResolution?: 'timestamp' | 'server-wins' | 'client-wins';
  batchSize?: number;
  respectEntityOrder?: boolean;
}
export interface SyncReport {
  totalActions: number;
  successful: number;
  failed: number;
  conflicts: number;
  details: SyncResult[];
}
export class SyncEngine {
  private actionQueue: ActionQueue;
  private supabaseClient: SupabaseClient;
  private defaultOptions: SyncOptions;
  constructor(queueFilePath?: string, mockServerPath?: string) {
    this.actionQueue = new ActionQueue(queueFilePath);
    this.supabaseClient = new SupabaseClient(mockServerPath);
    this.defaultOptions = {
      conflictResolution: 'timestamp',
      batchSize: 10,
      respectEntityOrder: true
    };
  }
  private groupActionsByEntity(actions: Action[]): Map<string, Action[]> {
    const entityGroups = new Map<string, Action[]>();
    
    for (const action of actions) {
      const entityId = action.id ? `${action.entity}:${action.id}` : `${action.entity}:new`;
      if (!entityGroups.has(entityId)) {
        entityGroups.set(entityId, []);
      }
      entityGroups.get(entityId)!.push(action);
    }
    // Sort actions within each entity group by timestamp to maintain order
    entityGroups.forEach((actionsGroup) => {
      actionsGroup.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
    });
    return entityGroups;
  }
  private async syncActionWithStrategy(action: Action, options: SyncOptions): Promise<SyncResult> {
    // Apply default conflict resolution if not specified in action
    const actionWithStrategy: Action = {
      ...action,
      conflict_resolution: action.conflict_resolution || options.conflictResolution
    };
    this.actionQueue.updateActionStatus(action.actionId, 'syncing');
    
    try {
      const result = await this.supabaseClient.syncAction(actionWithStrategy);
      
      if (result.success) {
        this.actionQueue.updateActionStatus(action.actionId, 'completed');
      } else {
        this.actionQueue.updateActionStatus(action.actionId, 'failed', (action.retryCount || 0) + 1);
      }
      
      return result;
    } catch (error) {
      this.actionQueue.updateActionStatus(action.actionId, 'failed', (action.retryCount || 0) + 1);
      return {
        success: false,
        actionId: action.actionId,
        error: (error as Error).message
      };
    }
  }
  async sync(options: Partial<SyncOptions> = {}): Promise<SyncReport> {
    const syncOptions = { ...this.defaultOptions, ...options };
    const pendingActions = this.actionQueue.getPendingActions();
    
    if (pendingActions.length === 0) {
      console.log('No pending actions to sync');
      return {
        totalActions: 0,
        successful: 0,
        failed: 0,
        conflicts: 0,
        details: []
      };
    }
    console.log(`Starting sync of ${pendingActions.length} pending actions`);
    
    let actionGroups: Action[][];
    
    if (syncOptions.respectEntityOrder) {
      // Group by entity+id to maintain order within logical entities
      const entityGroups = this.groupActionsByEntity(pendingActions);
      actionGroups = Array.from(entityGroups.values());
    } else {
      // Process all actions individually
      actionGroups = pendingActions.map(action => [action]);
    }
    const results: SyncResult[] = [];
    let successful = 0;
    let failed = 0;
    let conflicts = 0;
    // Process action groups in batches
    for (let i = 0; i < actionGroups.length; i += syncOptions.batchSize!) {
      const batch = actionGroups.slice(i, i + syncOptions.batchSize!);
      
      console.log(`Processing batch ${Math.floor(i / syncOptions.batchSize!) + 1}/${Math.ceil(actionGroups.length / syncOptions.batchSize!)}`);
      
      const batchPromises = batch.map(async (actionGroup) => {
        const groupResults: SyncResult[] = [];
        
        // Process actions within a group sequentially to maintain order
        for (const action of actionGroup) {
          console.log(`Syncing action ${action.actionId} (${action.type} ${action.entity})`);
          const result = await this.syncActionWithStrategy(action, syncOptions);
          groupResults.push(result);
          
          if (result.success) {
            successful++;
            console.log(`✓ Action ${action.actionId} synced successfully`);
          } else {
            failed++;
            if (result.conflict) {
              conflicts++;
              console.log(`⚠ Action ${action.actionId} conflict: ${result.error}`);
            } else {
              console.log(`✗ Action ${action.actionId} failed: ${result.error}`);
            }
          }
        }
        
        return groupResults;
      });
      
      const batchResults = await Promise.all(batchPromises);
      results.push(...batchResults.flat());
    }
    const report: SyncReport = {
      totalActions: pendingActions.length,
      successful,
      failed,
      conflicts,
      details: results
    };
    console.log('\n--- Sync Report ---');
    console.log(`Total: ${report.totalActions}`);
    console.log(`Successful: ${report.successful}`);
    console.log(`Failed: ${report.failed}`);
    console.log(`Conflicts: ${report.conflicts}`);
    console.log('-------------------\n');
    return report;
  }
  getQueue(): ActionQueue {
    return this.actionQueue;
  }
  getClient(): SupabaseClient {
    return this.supabaseClient;
  }
}
