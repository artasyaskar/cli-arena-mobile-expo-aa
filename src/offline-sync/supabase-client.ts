import { spawn } from 'child_process';
import * as path from 'path';
import { Action } from './action-queue';
export interface SyncResult {
  success: boolean;
  actionId: string;
  operation?: string;
  conflict?: boolean;
  error?: string;
  data?: any;
}
export class SupabaseClient {
  private mockServerPath: string;
  private retryConfig: {
    maxRetries: number;
    baseDelay: number;
    maxDelay: number;
    jitterFactor: number;
  };
  constructor(mockServerPath?: string) {
    this.mockServerPath = mockServerPath || path.resolve(__dirname, '../../tasks/cli-offline-user-sync/resources/mock_server.sh');
    this.retryConfig = {
      maxRetries: 3,
      baseDelay: 1000,
      maxDelay: 10000,
      jitterFactor: 0.1
    };
  }
  private async callMockServer(action: Action): Promise<any> {
    return new Promise((resolve, reject) => {
      const child = spawn('bash', [this.mockServerPath], {
        stdio: ['pipe', 'pipe', 'pipe']
      });
      let stdout = '';
      let stderr = '';
      child.stdout.on('data', (data) => {
        stdout += data.toString();
      });
      child.stderr.on('data', (data) => {
        stderr += data.toString();
      });
      child.on('close', (code) => {
        if (code === 0) {
          try {
            const response = JSON.parse(stdout.trim());
            resolve(response);
          } catch (error) {
            reject(new Error(`Failed to parse response: ${stdout}`));
          }
        } else {
          reject(new Error(`Mock server exited with code ${code}: ${stderr}`));
        }
      });
      child.on('error', (error) => {
        reject(error);
      });
      // Send the action as JSON to stdin
      child.stdin.write(JSON.stringify(action));
      child.stdin.end();
    });
  }
  private calculateDelay(attempt: number): number {
    const delay = this.retryConfig.baseDelay * Math.pow(2, attempt);
    const jitter = delay * this.retryConfig.jitterFactor * Math.random();
    return Math.min(delay + jitter, this.retryConfig.maxDelay);
  }
  private async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
  async syncAction(action: Action): Promise<SyncResult> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt <= this.retryConfig.maxRetries; attempt++) {
      try {
        const response = await this.callMockServer(action);
        
        if (response.status === 'success') {
          return {
            success: true,
            actionId: action.actionId,
            operation: response.operation,
            data: response.data
          };
        } else if (response.status === 'conflict') {
          return {
            success: false,
            actionId: action.actionId,
            conflict: true,
            error: response.message,
            data: response.server_item || response.existing_item
          };
        } else if (response.status === 'error') {
          // Check if this is a retryable error
          if (response.message?.includes('network') || response.message?.includes('timeout')) {
            lastError = new Error(response.message);
            if (attempt < this.retryConfig.maxRetries) {
              const delay = this.calculateDelay(attempt);
              console.log(`Network error, retrying in ${delay}ms (attempt ${attempt + 1}/${this.retryConfig.maxRetries + 1})`);
              await this.sleep(delay);
              continue;
            }
          }
          
          return {
            success: false,
            actionId: action.actionId,
            error: response.message
          };
        }
      } catch (error) {
        lastError = error as Error;
        if (attempt < this.retryConfig.maxRetries) {
          const delay = this.calculateDelay(attempt);
          console.log(`Request failed, retrying in ${delay}ms (attempt ${attempt + 1}/${this.retryConfig.maxRetries + 1}): ${error}`);
          await this.sleep(delay);
        }
      }
    }
    return {
      success: false,
      actionId: action.actionId,
      error: lastError?.message || 'Max retries exceeded'
    };
  }
  setRetryConfig(config: Partial<typeof this.retryConfig>): void {
    this.retryConfig = { ...this.retryConfig, ...config };
  }
}
