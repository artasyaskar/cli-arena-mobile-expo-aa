import { Command } from 'commander';
import { ActionQueue } from './action-queue';
import { SyncEngine } from './sync-engine';
import * as fs from 'fs';
import * as path from 'path';
interface CLIConfig {
  queueFile: string;
  conflictResolution: 'timestamp' | 'server-wins' | 'client-wins';
  maxRetries: number;
  baseDelay: number;
}
class OfflineSyncCLI {
  private config: CLIConfig;
  private actionQueue: ActionQueue;
  private syncEngine: SyncEngine;
  constructor() {
    this.config = this.loadConfig();
    this.actionQueue = new ActionQueue(this.config.queueFile);
    this.syncEngine = new SyncEngine(this.config.queueFile);
    
    // Configure retry settings
    this.syncEngine.getClient().setRetryConfig({
      maxRetries: this.config.maxRetries,
      baseDelay: this.config.baseDelay
    });
  }
  private loadConfig(): CLIConfig {
    const configPath = path.resolve('./sync-config.json');
    const defaultConfig: CLIConfig = {
      queueFile: './actions_queue.json',
      conflictResolution: 'timestamp',
      maxRetries: 3,
      baseDelay: 1000
    };
    if (fs.existsSync(configPath)) {
      try {
        const userConfig = JSON.parse(fs.readFileSync(configPath, 'utf8'));
        return { ...defaultConfig, ...userConfig };
      } catch (error) {
        console.warn('Failed to parse config file, using defaults');
      }
    }
    return defaultConfig;
  }
  createAction(type: 'CREATE' | 'UPDATE' | 'DELETE', entity: string, options: any): string {
    const action: any = {
      type,
      entity,
      conflict_resolution: options.conflictResolution || this.config.conflictResolution
    };
    if (type === 'CREATE') {
      if (!options.payload) {
        throw new Error('CREATE action requires payload');
      }
      action.payload = JSON.parse(options.payload);
    } else if (type === 'UPDATE') {
      if (!options.id || !options.payload) {
        throw new Error('UPDATE action requires id and payload');
      }
      action.id = options.id;
      action.payload = JSON.parse(options.payload);
    } else if (type === 'DELETE') {
      if (!options.id) {
        throw new Error('DELETE action requires id');
      }
      action.id = options.id;
    }
    const actionId = this.actionQueue.addAction(action);
    console.log(`Action ${actionId} added to queue (${type} ${entity})`);
    return actionId;
  }
  async performSync(options: any): Promise<void> {
    const syncOptions = {
      conflictResolution: options.conflictResolution || this.config.conflictResolution,
      batchSize: options.batchSize || 10,
      respectEntityOrder: !options.noEntityOrder
    };
    console.log('Starting synchronization...');
    const report = await this.syncEngine.sync(syncOptions);
    
    if (report.totalActions > 0) {
      console.log('\n=== Detailed Results ===');
      report.details.forEach((result, index) => {
        const status = result.success ? '✓' : (result.conflict ? '⚠' : '✗');
        console.log(`${index + 1}. ${status} ${result.actionId}: ${result.error || 'Success'}`);
      });
    }
  }
  showStatus(): void {
    const allActions = this.actionQueue.getAllActions();
    const pending = allActions.filter(a => a.status === 'pending').length;
    const completed = allActions.filter(a => a.status === 'completed').length;
    const failed = allActions.filter(a => a.status === 'failed').length;
    const syncing = allActions.filter(a => a.status === 'syncing').length;
    console.log('=== Queue Status ===');
    console.log(`Total actions: ${allActions.length}`);
    console.log(`Pending: ${pending}`);
    console.log(`Syncing: ${syncing}`);
    console.log(`Completed: ${completed}`);
    console.log(`Failed: ${failed}`);
    if (pending > 0) {
      console.log('\n=== Pending Actions ===');
      allActions
        .filter(a => a.status === 'pending')
        .forEach((action, index) => {
          console.log(`${index + 1}. ${action.actionId} - ${action.type} ${action.entity} (${action.timestamp})`);
        });
    }
    if (failed > 0) {
      console.log('\n=== Failed Actions ===');
      allActions
        .filter(a => a.status === 'failed')
        .forEach((action, index) => {
          console.log(`${index + 1}. ${action.actionId} - ${action.type} ${action.entity} (retries: ${action.retryCount || 0})`);
        });
    }
  }
  clearQueue(): void {
    this.actionQueue.clear();
    console.log('Queue cleared');
  }
  setupCommands(): Command {
    const program = new Command();
    program
      .name('offline-sync')
      .description('CLI for offline action synchronization with Supabase')
      .version('1.0.0');
    program
      .command('create')
      .description('Create a new record')
      .requiredOption('-e, --entity <entity>', 'Entity type (users, posts, etc.)')
      .requiredOption('-p, --payload <payload>', 'JSON payload for the new record')
      .option('-r, --conflict-resolution <strategy>', 'Conflict resolution strategy', 'timestamp')
      .action((options) => {
        try {
          this.createAction('CREATE', options.entity, options);
        } catch (error) {
          console.error('Error:', (error as Error).message);
          process.exit(1);
        }
      });
    program
      .command('update')
      .description('Update an existing record')
      .requiredOption('-e, --entity <entity>', 'Entity type (users, posts, etc.)')
      .requiredOption('-i, --id <id>', 'Record ID to update')
      .requiredOption('-p, --payload <payload>', 'JSON payload with updates')
      .option('-r, --conflict-resolution <strategy>', 'Conflict resolution strategy', 'timestamp')
      .action((options) => {
        try {
          this.createAction('UPDATE', options.entity, options);
        } catch (error) {
          console.error('Error:', (error as Error).message);
          process.exit(1);
        }
      });
    program
      .command('delete')
      .description('Delete a record')
      .requiredOption('-e, --entity <entity>', 'Entity type (users, posts, etc.)')
      .requiredOption('-i, --id <id>', 'Record ID to delete')
      .option('-r, --conflict-resolution <strategy>', 'Conflict resolution strategy', 'force-delete')
      .action((options) => {
        try {
          this.createAction('DELETE', options.entity, options);
        } catch (error) {
          console.error('Error:', (error as Error).message);
          process.exit(1);
        }
      });
    program
      .command('sync')
      .description('Synchronize pending actions with server')
      .option('-r, --conflict-resolution <strategy>', 'Conflict resolution strategy')
      .option('-b, --batch-size <size>', 'Batch size for sync operations', '10')
      .option('--no-entity-order', 'Disable entity order preservation')
      .action(async (options) => {
        try {
          await this.performSync({
            ...options,
            batchSize: parseInt(options.batchSize)
          });
        } catch (error) {
          console.error('Sync error:', (error as Error).message);
          process.exit(1);
        }
      });
    program
      .command('status')
      .description('Show queue status and pending actions')
      .action(() => {
        this.showStatus();
      });
    program
      .command('clear')
      .description('Clear all actions from queue')
      .action(() => {
        this.clearQueue();
      });
    return program;
  }
}
export { OfflineSyncCLI };
// CLI entry point
if (require.main === module) {
  const cli = new OfflineSyncCLI();
  const program = cli.setupCommands();
  program.parse();
}
