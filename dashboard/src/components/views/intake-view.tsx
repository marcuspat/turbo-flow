"use client";

import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { Inbox, FileText, Clock } from 'lucide-react';

interface IntakeFile {
  name: string;
  size: number;
  modified: string;
  preview: string;
}

export function IntakeView() {
  const [files, setFiles] = useState<IntakeFile[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/intake')
      .then((r) => r.json())
      .then((data) => setFiles(data.files || []))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="p-4 lg:p-6 max-w-4xl">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-lg font-semibold">Intake Inbox</h2>
          <p className="text-sm text-muted-foreground">
            {files.length} undistilled capture{files.length !== 1 ? 's' : ''} awaiting triage
          </p>
        </div>
        {files.length > 0 && (
          <Badge variant="secondary" className="gap-1">
            <Inbox className="h-3 w-3" /> {files.length}
          </Badge>
        )}
      </div>

      {loading ? (
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-16 w-full rounded-lg" />
          ))}
        </div>
      ) : files.length === 0 ? (
        <div className="flex flex-col items-center py-12 text-muted-foreground">
          <Inbox className="h-10 w-10 mb-2" />
          <p className="text-sm">Inbox is empty</p>
          <p className="text-xs mt-1">Captures will appear here before distillation</p>
        </div>
      ) : (
        <div className="space-y-2">
          {files.map((f) => (
            <Card key={f.name} className="hover:bg-muted/30 transition-colors">
              <CardContent className="p-3 flex items-start gap-3">
                <FileText className="h-4 w-4 text-muted-foreground mt-0.5 shrink-0" />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-mono break-all">{f.preview}</p>
                  <div className="flex items-center gap-3 mt-1.5 text-[10px] text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <Clock className="h-3 w-3" />
                      {new Date(f.modified).toLocaleString()}
                    </span>
                    <span>{f.size}B</span>
                    <span className="font-mono">{f.name}</span>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
