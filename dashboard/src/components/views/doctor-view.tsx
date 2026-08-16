"use client";

import React from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Shield, ShieldCheck, ShieldAlert, FileText, Hash, HardDrive,
  CheckCircle2, XCircle, AlertTriangle, RefreshCw,
} from 'lucide-react';

interface DoctorData {
  toolchain: { git: boolean; python3: boolean; rg: boolean };
  vault: {
    filesByCategory: Record<string, number>;
    totalFiles: number;
    totalFacts: number;
    sizeBytes: number;
    sizeKB: number;
    d4Trigger: boolean;
  };
  denyList: { present: boolean; terms: number; status: string };
  intake: { undistilled: number };
  lint: { passed: boolean | null; errors: number };
  timestamp: string;
  hooks?: Record<string, boolean>;
}

export function DoctorView({ data, onRefresh }: { data: DoctorData | null; onRefresh: () => void }) {
  if (!data) {
    return (
      <div className="p-4 lg:p-6 max-w-3xl">
        <div className="flex items-center gap-2 text-muted-foreground">
          <RefreshCw className="h-4 w-4 animate-spin" /> Loading...
        </div>
      </div>
    );
  }

  const catLabels: Record<string, string> = {
    profile: 'Profile', areas: 'Areas', people: 'People',
    projects: 'Projects', topics: 'Topics', daily: 'Daily',
  };

  return (
    <div className="p-4 lg:p-6 max-w-3xl">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-lg font-semibold">Vault Doctor</h2>
          <p className="text-sm text-muted-foreground">Environment, gates, and health checks</p>
        </div>
        <Button variant="outline" size="sm" onClick={onRefresh}>
          <RefreshCw className="h-3.5 w-3.5 mr-1" /> Refresh
        </Button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Toolchain */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Toolchain</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5">
            {Object.entries(data.toolchain).map(([tool, ok]) => (
              <div key={tool} className="flex items-center justify-between text-xs">
                <span className="font-mono text-muted-foreground">{tool}</span>
                {ok ? (
                  <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600" />
                ) : (
                  <XCircle className="h-3.5 w-3.5 text-destructive" />
                )}
              </div>
            ))}
          </CardContent>
        </Card>

        {/* Vault stats */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Vault Stats</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1.5">
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground flex items-center gap-1">
                <FileText className="h-3 w-3" /> Files
              </span>
              <span className="font-mono">{data.vault.totalFiles}</span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground flex items-center gap-1">
                <Hash className="h-3 w-3" /> Facts
              </span>
              <span className="font-mono">{data.vault.totalFacts}</span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground flex items-center gap-1">
                <HardDrive className="h-3 w-3" /> Size
              </span>
              <span className="font-mono">{data.vault.sizeKB} KB</span>
            </div>
            {data.vault.d4Trigger && (
              <div className="flex items-center gap-1 text-xs text-amber-600">
                <AlertTriangle className="h-3 w-3" />
                D4 index trigger fired
              </div>
            )}
          </CardContent>
        </Card>

        {/* Files by category */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm">Files by Category</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-1.5">
              {Object.entries(data.vault.filesByCategory).map(([cat, count]) => (
                <Badge key={cat} variant="outline" className="text-xs">
                  {catLabels[cat] || cat}: {count}
                </Badge>
              ))}
            </div>
          </CardContent>
        </Card>

        {/* Gates */}
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm flex items-center gap-1.5">
              <Shield className="h-4 w-4" />
              Privacy Gates (D8)
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {/* Deny list */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5">
                {data.denyList.terms > 0 ? (
                  <ShieldCheck className="h-4 w-4 text-emerald-600" />
                ) : (
                  <ShieldAlert className="h-4 w-4 text-amber-600" />
                )}
                <span className="text-xs">Deny List (L1)</span>
              </div>
              <Badge
                variant={data.denyList.terms > 0 ? 'default' : 'destructive'}
                className="text-[9px]"
              >
                {data.denyList.status}
              </Badge>
            </div>
            {/* Secret scan */}
            <div className="flex items-center justify-between">
              <span className="text-xs">Secret Scan (L2)</span>
              <CheckCircle2 className="h-4 w-4 text-emerald-600" />
            </div>
            {/* Lint */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-1.5">
                {data.lint.passed ? (
                  <CheckCircle2 className="h-4 w-4 text-emerald-600" />
                ) : (
                  <XCircle className="h-4 w-4 text-destructive" />
                )}
                <span className="text-xs">Schema Lint (D3)</span>
              </div>
              <Badge
                variant={data.lint.passed ? 'default' : 'destructive'}
                className="text-[9px]"
              >
                {data.lint.errors >= 0 ? `${data.lint.errors} errors` : 'failed'}
              </Badge>
            </div>
            {/* Intake */}
            <div className="flex items-center justify-between">
              <span className="text-xs">Intake Queue</span>
              <span className="text-xs font-mono text-muted-foreground">
                {data.intake.undistilled} undistilled
              </span>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
