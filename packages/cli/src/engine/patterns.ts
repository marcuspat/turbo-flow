// ─── Vendored resilience patterns ─────────────────────────────────
// Sourced from the competitive analysis (RUFLO-REUSE-ASSESSMENT.md):
//   - CircuitBreaker + RetryBudget from metaharness/recovery.ts
//   - Typed TerminationReason already in state.ts
//
// These are kept minimal. The engine itself handles the bounded loop;
// these patterns exist for future host adapters and for the retry-with-
// backoff logic when Claude returns transient errors.

/** Circuit breaker states */
export type CircuitState = 'closed' | 'open' | 'half_open';

/** A circuit breaker that trips after N consecutive failures. */
export class CircuitBreaker {
  private failures = 0;
  private lastFailureAt = 0;
  private _state: CircuitState = 'closed';

  constructor(
    private readonly failureThreshold = 3,
    private readonly resetMs = 60_000,
  ) {}

  get state(): CircuitState {
    if (this._state === 'open') {
      if (Date.now() - this.lastFailureAt >= this.resetMs) {
        this._state = 'half_open';
      }
    }
    return this._state;
  }

  /** Whether a call should be attempted */
  get allow(): boolean {
    return this.state !== 'open';
  }

  /** Record a success — resets the failure counter */
  success(): void {
    this.failures = 0;
    this._state = 'closed';
  }

  /** Record a failure — may trip the breaker */
  fail(): void {
    this.failures++;
    this.lastFailureAt = Date.now();
    if (this.failures >= this.failureThreshold) {
      this._state = 'open';
    }
  }

  /** Reset the breaker manually */
  reset(): void {
    this.failures = 0;
    this._state = 'closed';
    this.lastFailureAt = 0;
  }
}

/** Budget-aware retry controller. Stops retrying when budget is thin. */
export class RetryBudget {
  private attempts = 0;
  private costAccumulator = 0;

  constructor(
    private readonly maxAttempts: number,
    private readonly maxCostUsd: number,
  ) {}

  /** Whether another retry is allowed */
  get allow(): boolean {
    if (this.attempts >= this.maxAttempts) return false;
    if (this.costAccumulator >= this.maxCostUsd) return false;
    return true;
  }

  /** Record an attempt with its cost */
  record(costUsd: number): void {
    this.attempts++;
    this.costAccumulator += costUsd;
  }

  get used(): number { return this.attempts; }
  get spent(): number { return this.costAccumulator; }
  get remaining(): number { return this.maxCostUsd - this.costAccumulator; }
}

/**
 * Classify a host execution result into a termination bucket.
 * Vendored concept from dream-machine's classifyEntrypointResult.
 *
 * Returns a structured reason rather than a raw exit code, making
 * it possible to take different actions for budget vs error vs done.
 */
export function classifyResult(result: {
  error?: string;
  costUsd: number;
  budgetUsd: number;
}): { shouldRetry: boolean; reason: string } {
  if (result.error) {
    // Transient errors that are worth retrying
    const transient = [
      'rate limit',
      'timeout',
      'ECONNRESET',
      'socket hang up',
      ' Claude returned is_error=true',
    ];
    const isTransient = transient.some(t => result.error!.toLowerCase().includes(t.toLowerCase()));
    return { shouldRetry: isTransient, reason: isTransient ? 'transient_error' : 'fatal_error' };
  }

  if (result.costUsd >= result.budgetUsd) {
    return { shouldRetry: false, reason: 'budget_exhausted' };
  }

  return { shouldRetry: false, reason: 'success' };
}
