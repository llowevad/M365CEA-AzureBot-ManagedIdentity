/**
 * A2A Client — forwards messages to the orchestrator endpoint.
 * No authentication required for outbound calls to the orchestrator.
 * Supports both aggregated (sendMessage) and streaming (streamMessage) consumption.
 */

import { AppConfig } from './config';

const REQUEST_TIMEOUT_MS = 30_000;
const RETRY_DELAY_MS = 1_000;
const MAX_RETRIES = 1;

export class A2AClient {
  private config: AppConfig;

  constructor(config: AppConfig) {
    this.config = config;
  }

  /**
   * Sends a user message to the A2A orchestrator and returns the aggregated response.
   */
  async sendMessage(userMessage: string, conversationId?: string): Promise<string> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      try {
        if (attempt > 0) {
          await this.delay(RETRY_DELAY_MS * attempt);
        }
        return await this.executeRequest(userMessage, conversationId);
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        console.error(`A2A request attempt ${attempt + 1} failed:`, lastError.message);

        // Don't retry on 4xx errors
        if (lastError.message.includes('Client error')) {
          break;
        }
      }
    }

    throw lastError;
  }

  /**
   * Streams a user message to the A2A orchestrator, calling onChunk for each text part as it arrives.
   */
  async streamMessage(
    userMessage: string,
    onChunk: (text: string) => void,
    conversationId?: string
  ): Promise<void> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      try {
        if (attempt > 0) {
          await this.delay(RETRY_DELAY_MS * attempt);
        }
        return await this.executeStreamingRequest(userMessage, onChunk, conversationId);
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        console.error(`A2A streaming request attempt ${attempt + 1} failed:`, lastError.message);

        if (lastError.message.includes('Client error')) {
          break;
        }
      }
    }

    throw lastError;
  }

  private async executeStreamingRequest(
    userMessage: string,
    onChunk: (text: string) => void,
    conversationId?: string
  ): Promise<void> {
    const url = `${this.config.a2aBaseUrl}${this.config.a2aPath}`;

    const body = this.buildRequestBody(userMessage, conversationId);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!response.ok) {
        const category = response.status >= 400 && response.status < 500 ? 'Client error' : 'Server error';
        throw new Error(`${category} ${response.status}: ${response.statusText}`);
      }

      await this.consumeSSEStreamWithCallback(response, onChunk);
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error('A2A request timed out after 30 seconds');
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  private async executeRequest(userMessage: string, conversationId?: string): Promise<string> {
    const url = `${this.config.a2aBaseUrl}${this.config.a2aPath}`;

    const body = this.buildRequestBody(userMessage, conversationId);

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'text/event-stream',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });

      if (!response.ok) {
        const category = response.status >= 400 && response.status < 500 ? 'Client error' : 'Server error';
        throw new Error(`${category} ${response.status}: ${response.statusText}`);
      }

      return await this.consumeSSEStream(response);
    } catch (error) {
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error('A2A request timed out after 30 seconds');
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }

  /**
   * Consumes an SSE stream and aggregates text parts from the response.
   * Falls back to JSON body parsing if response is not SSE.
   */
  private async consumeSSEStream(response: Response): Promise<string> {
    const contentType = response.headers.get('content-type') || '';

    // If the response is plain JSON (not SSE), parse directly
    if (contentType.includes('application/json')) {
      const json = await response.json() as A2AJsonResponse;
      return this.extractTextFromJsonResponse(json);
    }

    // SSE stream consumption
    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('No response body available');
    }

    const decoder = new TextDecoder();
    const textParts: string[] = [];
    let buffer = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6).trim();
            if (data === '[DONE]') continue;

            try {
              const event = JSON.parse(data) as A2ASSEEvent;
              const text = this.extractTextFromEvent(event);
              if (text) textParts.push(text);
            } catch {
              // Skip malformed SSE data lines
            }
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    if (textParts.length === 0) {
      throw new Error('No text content received from A2A endpoint');
    }

    return textParts.join('');
  }

  private extractTextFromEvent(event: A2ASSEEvent): string | null {
    // Handle A2A protocol: result.parts[].text
    if (event.result?.parts) {
      return event.result.parts
        .filter((p) => p.kind === 'text' && p.text)
        .map((p) => p.text)
        .join('');
    }
    // Handle artifact updates
    if (event.params?.artifact?.parts) {
      return event.params.artifact.parts
        .filter((p) => p.kind === 'text' && p.text)
        .map((p) => p.text)
        .join('');
    }
    return null;
  }

  private extractTextFromJsonResponse(json: A2AJsonResponse): string {
    // Standard JSON-RPC response with result.parts
    if (json.result?.parts) {
      const text = json.result.parts
        .filter((p) => p.kind === 'text' && p.text)
        .map((p) => p.text)
        .join('');
      if (text) return text;
    }
    // Fallback: check for error
    if (json.error) {
      throw new Error(`A2A error ${json.error.code}: ${json.error.message}`);
    }
    throw new Error('Unexpected A2A response format');
  }

  private buildRequestBody(userMessage: string, conversationId?: string) {
    return {
      jsonrpc: '2.0',
      id: crypto.randomUUID(),
      method: 'message/send',
      params: {
        message: {
          kind: 'message',
          messageId: crypto.randomUUID(),
          role: 'user',
          parts: [{ kind: 'text', text: userMessage }],
          ...(conversationId && { contextId: conversationId }),
        },
      },
    };
  }

  /**
   * Consumes an SSE stream, calling onChunk for each text part as it arrives.
   * Falls back to JSON body parsing if response is not SSE.
   */
  private async consumeSSEStreamWithCallback(
    response: Response,
    onChunk: (text: string) => void
  ): Promise<void> {
    const contentType = response.headers.get('content-type') || '';

    if (contentType.includes('application/json')) {
      const json = await response.json() as A2AJsonResponse;
      onChunk(this.extractTextFromJsonResponse(json));
      return;
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('No response body available');
    }

    const decoder = new TextDecoder();
    let buffer = '';
    let receivedAny = false;

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6).trim();
            if (data === '[DONE]') continue;

            try {
              const event = JSON.parse(data) as A2ASSEEvent;
              const text = this.extractTextFromEvent(event);
              if (text) {
                onChunk(text);
                receivedAny = true;
              }
            } catch {
              // Skip malformed SSE data lines
            }
          }
        }
      }
    } finally {
      reader.releaseLock();
    }

    if (!receivedAny) {
      throw new Error('No text content received from A2A endpoint');
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

// A2A protocol types (minimal for parsing)
interface A2APart {
  kind: string;
  text?: string;
}

interface A2ASSEEvent {
  result?: { parts?: A2APart[] };
  params?: { artifact?: { parts?: A2APart[] } };
}

interface A2AJsonResponse {
  result?: { parts?: A2APart[] };
  error?: { code: number; message: string };
}
