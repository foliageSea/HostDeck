/// Typed failures of the AI agent feature.
///
/// They extend [StateError] so existing `on StateError` handlers keep working,
/// while callers that care can branch on the type or [code] instead of
/// matching message text. [message] is always safe to show to API clients.
class AiAgentException extends StateError {
  /// Stable, machine-readable identifier sent to clients (e.g. in SSE events).
  final String code;

  AiAgentException(super.message, {required this.code});
}

/// No usable credential is stored for the selected provider.
class AiAgentApiKeyNotConfiguredException extends AiAgentException {
  AiAgentApiKeyNotConfiguredException()
    : super('API key is not configured.', code: 'API_KEY_NOT_CONFIGURED');
}

/// The model asked for more tool calls than a single run may execute.
class AiAgentToolCallLimitException extends AiAgentException {
  AiAgentToolCallLimitException()
    : super('Tool call limit exceeded.', code: 'TOOL_CALL_LIMIT');
}

/// A run exceeded its maximum wall-clock duration.
class AiAgentRunTimeoutException extends AiAgentException {
  AiAgentRunTimeoutException() : super('Run timed out.', code: 'RUN_TIMEOUT');
}

/// A new run was refused because of a concurrency rule (HTTP 409).
class AiAgentRunConflictException extends AiAgentException {
  AiAgentRunConflictException.conversationBusy()
    : super(
        'A run is already active for this conversation.',
        code: 'RUN_CONFLICT',
      );

  AiAgentRunConflictException.capacityReached()
    : super('Too many AI agent runs are active.', code: 'RUN_CAPACITY');
}
