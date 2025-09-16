import WebSocket from 'ws';
import { parse } from 'graphql';
import { SubscriptionConfig, ConnectionStatus } from './types/subscription';

export class GraphQLSubscriber {
  private ws: WebSocket | null = null;
  private status: ConnectionStatus = { connected: false };
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;

  constructor(private config: SubscriptionConfig) {}

  connect() {
    try {
      // Validate query
      parse(this.config.query);

      this.ws = new WebSocket(this.config.endpoint);

      this.ws.on('open', () => {
        console.log('Connected to GraphQL endpoint');
        this.status.connected = true;
        this.initSubscription();
      });

      this.ws.on('message', (data) => {
        const response = JSON.parse(data.toString());
        if (response.payload) {
          this.config.onData(response.payload.data);
        }
      });

      this.ws.on('error', (error) => {
        this.status.lastError = error.message;
        if (this.config.onError) {
          this.config.onError(error);
        }
      });

      this.ws.on('close', () => {
        this.status.connected = false;
        this.handleReconnect();
      });

    } catch (error) {
      console.error('Failed to establish connection:', error);
      throw error;
    }
  }

  private initSubscription() {
    if (!this.ws) return;
    
    const message = {
      type: 'start',
      id: '1',
      payload: {
        query: this.config.query,
        variables: this.config.variables
      }
    };

    this.ws.send(JSON.stringify(message));
  }

  private handleReconnect() {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      this.status.reconnectAttempt = this.reconnectAttempts;
      console.log(`Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
      setTimeout(() => this.connect(), 2000 * this.reconnectAttempts);
    } else {
      console.error('Max reconnection attempts reached');
    }
  }

  disconnect() {
    if (this.ws) {
      this.ws.close();
    }
  }

  getStatus(): ConnectionStatus {
    return this.status;
  }
}
