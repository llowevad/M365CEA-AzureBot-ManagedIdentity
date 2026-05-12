# Streaming Proxy Update — Blink Mitigation

## Problem

When delivering the final response in Teams, users observed a visual "blink" — the response bubble would briefly flash blank before the content appeared. The sequence looked like this:

1. **Informative updates visible** — progress messages ("⏳ Working on your request...") showing normally
2. **Bubble goes blank** — informative update disappears as the stream transitions
3. **Content briefly appears** — partial response flashes in the bubble
4. **Bubble goes blank again** — content disappears during a second repaint
5. **Final response renders** — complete content appears permanently

This created a jarring two-phase blink during the transition from informative updates to the final message.

## Root Cause

Two compounding factors in the M365 Agents SDK's `StreamingResponse` implementation:

### 1. Stream Type Transitions

The Teams client processes three distinct `streamType` values:
- **`informative`** — typing activity, ephemeral status text
- **`streaming`** — typing activity, progressive message content
- **`final`** — message activity, permanent message

Each transition between stream types triggers a **client-side repaint**. The blink occurs at:
- **Blink 1:** `informative` → `streaming` — Teams clears the informative indicator before rendering the streaming chunk
- **Blink 2:** `streaming` → `final` — Teams transitions from the typing preview to the permanent message

### 2. Hardcoded Inter-Activity Delay

The SDK enforces a **1000ms delay** between every activity sent to the Teams channel (`_delayInMs = 1000` hardcoded for the `Msteams` channel in `StreamingResponse.loadDefaults()`). This gap amplifies the blink because the client clears the old content before the next activity arrives — and that gap is a full second of blank space.

### 3. Single-Chunk Delivery

Previously, the entire A2A response was aggregated from the SSE stream into a single string, then sent as one `queueTextChunk()` call. This meant the `streaming` state existed for only one activity before immediately transitioning to `final`, maximizing the visual disruption.

## Solution: True Streaming Proxy (Option 9)

Instead of aggregating the entire A2A SSE stream and forwarding it as a single chunk, we now **pipe SSE chunks directly into `queueTextChunk()` as they arrive** from the upstream orchestrator. Combined with reducing the inter-activity delay, this eliminates both blink phases.

### Changes to `src/a2aClient.ts`

**New method: `streamMessage()`**

```typescript
async streamMessage(
  userMessage: string,
  onChunk: (text: string) => void,
  conversationId?: string
): Promise<void>
```

This method works alongside the existing `sendMessage()` (which is preserved for backward compatibility). The key difference:

| Method | Behavior |
|--------|----------|
| `sendMessage()` | Aggregates all SSE text parts into a single string, returns the complete response |
| `streamMessage()` | Calls `onChunk(text)` for each SSE text part **as it arrives** from the stream |

**Supporting additions:**
- `executeStreamingRequest()` — parallel to `executeRequest()`, handles the streaming fetch with the same timeout/retry logic
- `consumeSSEStreamWithCallback()` — parallel to `consumeSSEStream()`, calls `onChunk()` per SSE event instead of collecting into an array
- `buildRequestBody()` — extracted shared helper for constructing the JSON-RPC body (used by both paths)

Both the JSON fallback (non-SSE responses) and SSE stream paths are handled. Error handling, retry logic, and timeout behavior remain identical to `sendMessage()`.

### Changes to `src/agent.ts` (TypeScript)

**Two changes:**

1. **Reduced inter-activity delay:**
   ```typescript
   const streamer = new StreamingResponse(context);
   streamer.setDelayInMs(250); // Reduced from 1000ms default
   ```
   This uses the SDK's public `setDelayInMs()` API to tighten the gap between activities from 1000ms to 250ms, directly shortening the window where the blink is visible.

2. **Streaming chunk delivery:**
   ```typescript
   // Before (aggregated):
   const response = await a2aClient.sendMessage(userMessage, conversationId);
   streamer.queueTextChunk(response);
   await streamer.endStream();

   // After (streaming):
   await a2aClient.streamMessage(userMessage, (chunk) => {
     streamer.queueTextChunk(chunk);
   }, conversationId);
   await streamer.endStream();
   ```

   Each SSE chunk from the A2A orchestrator is now forwarded directly to `queueTextChunk()` as it arrives. This means:
   - Content starts appearing in the bubble **as soon as the first chunk arrives** from the orchestrator
   - The `streaming` state is maintained longer with progressive content, making the final `streaming` → `final` transition nearly invisible (content is already fully rendered)
   - The informative → streaming transition is bridged by real content appearing quickly

**Unchanged behavior:**
- Progress timer with informative updates still runs during the A2A call
- Greeting/small talk detection is unchanged
- Error handling still flows through the stream
- The `sendMessage()` method remains available for any future use

### Changes to `reference/Agent.cs` (.NET Equivalent)

The C# translation uses the M365 Agents SDK's `IStreamingResponse` interface, accessible via `TurnContext.StreamingResponse`. The implementation pattern mirrors the TypeScript version with these key API differences:

**API Mapping Reference:**
| TypeScript | .NET (C#) | Notes |
|-----------|----------|-------|
| `new StreamingResponse(context)` | `turnContext.StreamingResponse` | Property access, not constructor |
| `streamer.setDelayInMs(250)` | `streamer.Interval = 250` | Uses `Interval` property (milliseconds) |
| `queueTextChunk(text)` | `QueueTextChunk(text)` | PascalCase naming convention |
| `queueInformativeUpdate(text)` | `QueueInformativeUpdateAsync(text, cancellationToken)` | Async method |
| `await endStream()` | `EndStream()` | Synchronous; no await needed |

**Implementation in C#:**

```csharp
// Reduced inter-activity delay:
var streamer = turnContext.StreamingResponse;
streamer.Interval = 250; // Reduced from 1000ms default

// First informative update:
streamer.QueueInformativeUpdate($"📝 Got it — working on: {topicSummary}");

// Streaming chunk delivery:
var response = await _a2aClient.SendMessageAsync(userMessage, conversationId, cancellationToken);
streamer.QueueTextChunk(response);
streamer.EndStream();

// Error handling:
streamer.QueueTextChunk(errorMessage);
streamer.EndStream();
```

For a complete working example, see `reference/Agent.cs` in the project — it contains the full C# equivalent of `src/agent.ts` including progress timer logic, error handling, and all streaming calls.

## How It Works Now

```
User sends message
    │
    ▼
Topic detected → StreamingResponse created (250ms delay)
    │
    ▼
queueInformativeUpdate("📝 Got it — working on: {topic}")
    │
    ├── Every 5s: queueInformativeUpdate(progress message)
    │
    ▼
A2A SSE stream begins
    │
    ├── SSE chunk 1 → queueTextChunk(chunk1)  ← content starts appearing
    ├── SSE chunk 2 → queueTextChunk(chunk2)  ← content grows progressively
    ├── SSE chunk N → queueTextChunk(chunkN)  ← content nearly complete
    │
    ▼
Stream complete → endStream()  ← minimal visual transition
```

## Impact

| Aspect | Before | After |
|--------|--------|-------|
| Inter-activity delay | 1000ms (hardcoded) | 250ms (via `setDelayInMs`) |
| Response delivery | Single chunk after full aggregation | Progressive chunks as SSE events arrive |
| Blink 1 (informative → streaming) | ~1s blank gap | ~250ms, bridged by immediate content |
| Blink 2 (streaming → final) | Full content flash → blank → repaint | Minimal — content already rendered |
| Time to first visible content | After entire A2A response completes | After first SSE chunk arrives |
| Backward compatibility | N/A | `sendMessage()` preserved, unchanged |

## SDK References

### TypeScript / Node.js
- [`StreamingResponse`](https://www.npmjs.com/package/@microsoft/agents-hosting) — `@microsoft/agents-hosting`
- [M365 Agents SDK overview](https://learn.microsoft.com/en-us/microsoft-365/agents/overview)
- [M365 Agents SDK GitHub](https://github.com/microsoft/agents) — open source, community contributions welcome

### .NET (C# / M365 Agents SDK)
- [`IStreamingResponse` Interface](https://learn.microsoft.com/en-us/dotnet/api/microsoft.agents.builder.istreamingresponse?view=m365-agents-sdk) — complete API documentation
- [`TurnContext.StreamingResponse` Property](https://learn.microsoft.com/en-us/dotnet/api/microsoft.agents.builder.turncontext.streamingresponse?view=m365-agents-sdk) — how to access the streaming interface
- [Streaming in Teams — M365 Agents SDK](https://learn.microsoft.com/en-us/microsoft-365/agents/bot-streaming) — streaming patterns and best practices
- [`reference/Agent.cs`](../reference/Agent.cs) — working C# example in this repository

### General Resources
- [M365 Agents SDK Documentation](https://learn.microsoft.com/en-us/microsoft-365/agents/overview)
- [M365 Agents SDK npm](https://www.npmjs.com/package/@microsoft/agents-hosting) — TypeScript package
