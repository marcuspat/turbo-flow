"use client";

import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Waves, CheckCircle2, XCircle, Clock, DollarSign, AlertTriangle, Loader2 } from 'lucide-react';

interface WaveResult {
  wave: string;
  timestamp?: string;
  dry_run?: boolean;
  budget_usd?: number;
  ready?: boolean;
  facts_before?: number;
  intake_items?: number;
  new_facts_proposed?: number;
  max_loss_allowed?: number;
  max_additions_allowed?: number;
  gates?: Record<string, { passed?: boolean; status?: string; detail?: string }>;
  items?: Array<{ file: string; action: string; gates: Array<{ name: string; passed: boolean }> }>;
  total_facts?: number;
  stale_waves?: Array<{ wave: string; age_hours: number; max: number }>;
  error?: string;
}

interface WaveStatus {
  lastSuccess: string | null;
  status: string;
}

const WAVE_INFO = {
  triage: { label: 'Triage', cadence: 'Daily 06:00', budget: '$0.50', color: 'text-amber-600' },
  distill: { label: 'Distill', cadence: 'Weekly Sun', budget: '$5.00', color: 'text-emerald-600' },
  sweep: { label: 'Sweep', cadence: 'Monthly', budget: '$3.00', color: 'text-violet-600' },
} as const;

export function WavesView() {
  const [results, setResults] = useState<Record<string, WaveResult>>({});
  const [waveStatus, setWaveStatus] = useState<Record<string, WaveStatus>>({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/waves')
      .then((r) => r.json())
      .then((data) => {
        setResults(data.results || {});
        setWaveStatus(data.waveStatus || {});
      })
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="p-4 lg:p-6 max-w-4xl">
      <h2 className="text-lg font-semibold mb-1">Distillation Waves</h2>
      <p className="text-sm text-muted-foreground mb-4">
        Scheduled invocations with budgets and gates — nothing resident
      </p>

      {loading ? (
        <div className="space-y-4">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-48 w-full rounded-lg" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          {(Object.entries(WAVE_INFO) as Array<[keyof typeof WAVE_INFO, typeof WAVE_INFO.triage]>).map(
            ([key, info]) => {
              const result = results[key];
              const status = waveStatus[key];
              return (
                <Card key={key}>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-sm flex items-center justify-between">
                      <span className="flex items-center gap-1.5">
                        <Waves className={`h-4 w-4 ${info.color}`} />
                        {info.label}
                      </span>
                      {status && (
                        <Badge
                          variant={
                            status.status === 'ok'
                              ? 'default'
                              : status.status === 'STALE'
                                ? 'destructive'
                                : 'secondary'
                          }
                          className="text-[9px]"
                        >
                          {status.status}
                        </Badge>
                      )}
                    </CardTitle>
                    <CardDescription className="text-xs">
                      {info.cadence} · <DollarSign className="h-3 w-3 inline" />{info.budget}
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-2">
                    {status?.lastSuccess && (
                      <div className="text-[10px] text-muted-foreground flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        Last: {new Date(status.lastSuccess).toLocaleString()}
                      </div>
                    )}

                    {result?.error ? (
                      <div className="flex items-center gap-1.5 text-xs text-destructive">
                        <XCircle className="h-3.5 w-3.5" /> {result.error}
                      </div>
                    ) : result?.gates ? (
                      <div className="space-y-1.5">
                        {Object.entries(result.gates).map(([gateName, gate]) => (
                          <div
                            key={gateName}
                            className="flex items-center gap-1.5 text-xs"
                          >
                            {gate.passed ? (
                              <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600" />
                            ) : (
                              <AlertTriangle className="h-3.5 w-3.5 text-amber-600" />
                            )}
                            <span className="text-muted-foreground font-mono text-[10px]">
                              {gateName}:
                            </span>
                            <span className={gate.passed ? 'text-emerald-700' : 'text-amber-700'}>
                              {gate.detail || (gate.passed ? 'pass' : 'fail')}
                            </span>
                          </div>
                        ))}
                      </div>
                    ) : null}

                    {key === 'distill' && result && 'facts_before' in result && (
                      <div className="text-[10px] text-muted-foreground border-t pt-2 mt-2 space-y-0.5">
                        <div>Facts in vault: {result.facts_before}</div>
                        <div>Intake items: {result.intake_items}</div>
                        <div>New facts: {result.new_facts_proposed}</div>
                      </div>
                    )}

                    {key === 'sweep' && result && 'total_facts' in result && (
                      <div className="text-[10px] text-muted-foreground border-t pt-2 mt-2">
                        Total facts: {result.total_facts}
                      </div>
                    )}

                    <div className="pt-1">
                      <Badge variant="outline" className="text-[9px]">
                        dry-run
                      </Badge>
                    </div>
                  </CardContent>
                </Card>
              );
            }
          )}
        </div>
      )}

      <Card className="mt-4">
        <CardContent className="p-4">
          <h3 className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-2">
            Wave Design (D7)
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 text-xs">
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">triage</Badge>
              <span className="text-muted-foreground">Classify inbox, route to target file</span>
            </div>
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">distill</Badge>
              <span className="text-muted-foreground">Intake to curated, propose deletions</span>
            </div>
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">sweep</Badge>
              <span className="text-muted-foreground">Staleness, contradictions, hygiene</span>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
