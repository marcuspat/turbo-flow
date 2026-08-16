"use client";

import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { CheckCircle2, AlertCircle, Zap } from 'lucide-react';

export function CaptureView() {
  const [text, setText] = useState('');
  const [result, setResult] = useState<{ ok: boolean; message: string } | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const handleCapture = async () => {
    if (!text.trim()) return;
    setSubmitting(true);
    setResult(null);
    try {
      const r = await fetch('/api/capture', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: text.trim() }),
      });
      const data = await r.json();
      setResult({ ok: r.ok, message: data.error || data.message });
      if (r.ok) setText('');
    } catch {
      setResult({ ok: false, message: 'Network error' });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="p-4 lg:p-6 max-w-2xl">
      <h2 className="text-lg font-semibold mb-1">Capture</h2>
      <p className="text-sm text-muted-foreground mb-4">
        A thought, observation, or fact. Stored as-is, zero tokens. Distillation happens later.
      </p>

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm flex items-center gap-2">
            <Zap className="h-4 w-4 text-primary" />
            Quick Capture
          </CardTitle>
          <CardDescription className="text-xs">
            One fact per capture. No LLM in the capture path — costs zero tokens.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Textarea
            placeholder="A thought, observation, or fact..."
            className="min-h-[100px] resize-y text-sm"
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) handleCapture();
            }}
          />
          <div className="flex items-center justify-between mt-3">
            <p className="text-[10px] text-muted-foreground">
              {text.length}/4000 · Cmd+Enter to submit
            </p>
            <Button size="sm" onClick={handleCapture} disabled={submitting || !text.trim()}>
              Capture
            </Button>
          </div>
          {result && (
            <div className={`mt-3 flex items-center gap-2 text-sm p-2 rounded-md ${
              result.ok ? 'bg-emerald-50 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300' :
              'bg-red-50 text-red-700 dark:bg-red-950 dark:text-red-300'
            }`}>
              {result.ok ? <CheckCircle2 className="h-4 w-4" /> : <AlertCircle className="h-4 w-4" />}
              {result.message}
            </div>
          )}
        </CardContent>
      </Card>

      <Card className="mt-4">
        <CardContent className="p-4">
          <h3 className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-2">
            Capture Design (D6)
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">D6</Badge>
              <span className="text-muted-foreground">iOS Shortcut → GitHub Contents API → inbox/</span>
            </div>
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">D6</Badge>
              <span className="text-muted-foreground">One file per capture — no merge conflicts</span>
            </div>
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">D6</Badge>
              <span className="text-muted-foreground">Zero tokens at capture time</span>
            </div>
            <div className="flex items-start gap-1.5">
              <Badge variant="outline" className="text-[9px] shrink-0 mt-0.5">D8</Badge>
              <span className="text-muted-foreground">Secret scan + deny gate on distill</span>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
