"use client";

import React, { useState, useEffect } from 'react';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { ScrollArea } from '@/components/ui/scroll-area';
import { FileText, Hash, FolderOpen } from 'lucide-react';
import type { VaultFile } from '../dashboard-shell';

const CATEGORIES = [
  { id: 'profile', label: 'Profile', icon: <FileText className="h-3.5 w-3.5" /> },
  { id: 'areas', label: 'Areas', icon: <FolderOpen className="h-3.5 w-3.5" /> },
  { id: 'people', label: 'People', icon: <FileText className="h-3.5 w-3.5" /> },
  { id: 'projects', label: 'Projects', icon: <FileText className="h-3.5 w-3.5" /> },
  { id: 'topics', label: 'Topics', icon: <FileText className="h-3.5 w-3.5" /> },
  { id: 'daily', label: 'Daily', icon: <FileText className="h-3.5 w-3.5" /> },
] as const;

const SENS_COLORS: Record<string, string> = {
  private: 'bg-red-100 text-red-700 dark:bg-red-950 dark:text-red-300',
  shareable: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300',
  public: 'bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300',
};

const TAG_COLORS: Record<string, string> = {
  stated: 'bg-primary/15 text-primary',
  ingested: 'bg-secondary text-secondary-foreground',
  derived: 'bg-accent text-accent-foreground',
};

export function VaultBrowser({ onSelectFile }: { onSelectFile: (f: VaultFile) => void }) {
  const [files, setFiles] = useState<VaultFile[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/files')
      .then((r) => r.json())
      .then(setFiles)
      .finally(() => setLoading(false));
  }, []);

  const filtered = filter ? files.filter((f) => f.category === filter) : files;
  const grouped = CATEGORIES.map((cat) => ({
    ...cat,
    files: filtered.filter((f) => f.category === cat.id),
  })).filter((g) => g.files.length > 0);

  return (
    <div className="p-4 lg:p-6 max-w-5xl">
      <div className="mb-4">
        <h2 className="text-lg font-semibold">Vault Browser</h2>
        <p className="text-sm text-muted-foreground">
          {files.length} files across {new Set(files.map(f => f.category)).size} categories
        </p>
      </div>

      {/* Category filter pills */}
      <div className="flex gap-1.5 mb-4 flex-wrap">
        <button
          onClick={() => setFilter(null)}
          className={`px-2.5 py-1 text-xs rounded-full border transition-colors ${
            !filter ? 'bg-primary text-primary-foreground border-primary' : 'hover:bg-muted'
          }`}
        >
          All
        </button>
        {CATEGORIES.map((cat) => {
          const count = files.filter((f) => f.category === cat.id).length;
          if (count === 0) return null;
          return (
            <button
              key={cat.id}
              onClick={() => setFilter(filter === cat.id ? null : cat.id)}
              className={`px-2.5 py-1 text-xs rounded-full border transition-colors flex items-center gap-1 ${
                filter === cat.id ? 'bg-primary text-primary-foreground border-primary' : 'hover:bg-muted'
              }`}
            >
              {cat.icon} {cat.label} <span className="opacity-60">{count}</span>
            </button>
          );
        })}
      </div>

      {loading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-20 w-full rounded-lg" />
          ))}
        </div>
      ) : (
        <div className="space-y-5">
          {grouped.map((group) => (
            <div key={group.id}>
              <div className="flex items-center gap-2 mb-2">
                <span className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                  {group.label}
                </span>
                <div className="flex-1 h-px bg-border" />
                <span className="text-xs text-muted-foreground">
                  {group.files.reduce((s, f) => s + f.factCount, 0)} facts
                </span>
              </div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                {group.files.map((file) => (
                  <Card
                    key={file.path}
                    className="cursor-pointer hover:bg-muted/50 transition-colors border-border/60"
                    onClick={() => onSelectFile(file)}
                  >
                    <CardContent className="p-3">
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-1.5 mb-1">
                            <span className="text-sm font-medium truncate">{file.name}</span>
                            <Badge
                              className={`text-[9px] px-1.5 py-0 ${SENS_COLORS[file.sensitivity] || ''}`}
                              variant="secondary"
                            >
                              {file.sensitivity}
                            </Badge>
                          </div>
                          <p className="text-xs text-muted-foreground line-clamp-2 leading-relaxed">
                            {file.description || 'No description'}
                          </p>
                        </div>
                        <div className="flex items-center gap-1 text-muted-foreground shrink-0">
                          <Hash className="h-3 w-3" />
                          <span className="text-xs font-mono">{file.factCount}</span>
                        </div>
                      </div>
                      {file.sources.length > 0 && (
                        <div className="flex gap-1 mt-2 flex-wrap">
                          {file.sources.map((s) => (
                            <Badge key={s} variant="outline" className="text-[9px] px-1.5 py-0">
                              {s}
                            </Badge>
                          ))}
                        </div>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
