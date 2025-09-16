import { GraphQLClient } from 'graphql-request';

export interface SubscriptionConfig {
  endpoint: string;
  query: string;
  variables?: Record<string, any>;
  onData: (data: any) => void;
  onError?: (error: any) => void;
}

export interface ConnectionStatus {
  connected: boolean;
  lastError?: string;
  reconnectAttempt?: number;
}
