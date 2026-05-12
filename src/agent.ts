/**
 * Agent — AgentApplication handler that relays messages to the A2A orchestrator.
 * Pure proxy: receive Activity → forward to A2A → return response as reply.
 */

import { AgentApplication, TurnContext, TurnState, StreamingResponse } from '@microsoft/agents-hosting';
import { A2AClient } from './a2aClient';
import { AppConfig } from './config';

// User-friendly error messages — never expose internals
const ERROR_MESSAGES = {
  timeout: "⏳ I'm taking longer than expected to respond. Please try again in a moment.",
  auth: '🔒 Authentication error — please contact your administrator.',
  unavailable: "⚠️ I'm having trouble reaching my backend service. Please try again shortly.",
  generic: "❌ Something went wrong. Please try again. If the issue persists, contact your administrator.",
};

export function createAgent(config: AppConfig): AgentApplication<TurnState> {
  const a2aClient = new A2AClient(config);

  const agent = new AgentApplication<TurnState>();

  agent.onActivity('message', async (context: TurnContext, _state: TurnState) => {
    const userMessage = context.activity.text?.trim();

    if (!userMessage) {
      await context.sendActivity('I can only process text messages. Please send me some text.');
      return;
    }

    // Detect greetings or messages with no clear topic
    if (isGreetingOrSmallTalk(userMessage)) {
      await context.sendActivity(
        'Hello! I\'m connected to the orchestrator. Send me a message with a topic and I\'ll get you an answer.\n\n' +
        'For example, try: *"Write a blog post about AI in healthcare"*'
      );
      return;
    }

    // User provided a topic — acknowledge it before processing
    const topicSummary = extractTopicSummary(userMessage);

    // Rotating friendly progress messages so the user sees real updates while waiting
    const PROGRESS_MESSAGES = [
      '⏳ Working on your request...',
      '🔄 Still processing — this might take a moment...',
      '🧠 The orchestrator is thinking...',
      '📝 Almost there...',
      '⚙️ Crunching the details...',
      '🔍 Gathering information...',
    ];

    const PROGRESS_INTERVAL_MS = 5_000;
    let progressIndex = 0;

    // Use the SDK's StreamingResponse for in-place progress updates
    const streamer = new StreamingResponse(context);
    streamer.setDelayInMs(250);

    // First informative update: the topic acknowledgment
    streamer.queueInformativeUpdate(`📝 Got it — working on: ${topicSummary}`);

    // Queue additional informative updates every 5 seconds
    const progressTimer = setInterval(() => {
      try {
        const msg = PROGRESS_MESSAGES[progressIndex % PROGRESS_MESSAGES.length];
        streamer.queueInformativeUpdate(msg);
        progressIndex++;
      } catch {
        // Best-effort — don't crash the handler if a progress update fails
      }
    }, PROGRESS_INTERVAL_MS);

    try {
      const conversationId = context.activity.conversation?.id;
      await a2aClient.streamMessage(userMessage, (chunk) => {
        streamer.queueTextChunk(chunk);
      }, conversationId);

      // Stop progress updates
      clearInterval(progressTimer);

      await streamer.endStream();
    } catch (error) {
      const errorMessage = categorizeError(error);
      console.error('A2A relay error:', error instanceof Error ? error.message : error);

      clearInterval(progressTimer);
      streamer.queueTextChunk(errorMessage);
      await streamer.endStream();
    } finally {
      clearInterval(progressTimer);
    }
  });

  return agent;
}

const GREETING_PATTERNS = /^(h(ello|i|ey|owdy)|good\s*(morning|afternoon|evening)|yo|sup|what'?s\s*up|greetings|thanks?|thank\s*you|ok(ay)?|sure|bye|goodbye|see\s*ya)[\s!?.]*$/i;

function isGreetingOrSmallTalk(message: string): boolean {
  const normalized = message.trim().toLowerCase();
  // Short messages (1-3 words) that match greeting patterns
  if (GREETING_PATTERNS.test(normalized)) return true;
  // Very short messages with no substance (1-2 words, not matching a topic)
  const wordCount = normalized.split(/\s+/).length;
  if (wordCount <= 2 && normalized.length < 15) return true;
  return false;
}

function extractTopicSummary(message: string): string {
  // Return the first 80 characters of the message as a topic summary
  if (message.length <= 80) return message;
  return message.substring(0, 77) + '...';
}

function categorizeError(error: unknown): string {
  if (!(error instanceof Error)) return ERROR_MESSAGES.generic;

  const msg = error.message.toLowerCase();

  if (msg.includes('timed out') || msg.includes('timeout')) {
    return ERROR_MESSAGES.timeout;
  }
  if (msg.includes('token acquisition') || msg.includes('authentication')) {
    return ERROR_MESSAGES.auth;
  }
  if (msg.includes('fetch failed') || msg.includes('econnrefused') || msg.includes('enotfound')) {
    return ERROR_MESSAGES.unavailable;
  }
  return ERROR_MESSAGES.generic;
}
