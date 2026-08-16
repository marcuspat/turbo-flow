"use client";

import React, { useState, useEffect, useCallback } from 'react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { Search, Loader2, AlertCircle } from 'lucide-react';
import type { VaultFile } from '../dashboard-shell';

interface SearchHit {
  file: string;
  line: number;
  text: string;
  category: string;
}

const TAG_COLORS: Record<string, string> = {
  stated: 'bg-primary/15 text-primary',
  ingested: 'bg-secondary text-secondary-foreground',
  derived: 'bg-accent text-accent-foreground',
};

export function SearchView({ initialQuery, onSelectFile }: { initialQuery: string; onSelectFile: (f: VaultFile) => void }) {
  const [query, setQuery] = useState(initialQuery);
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  const doSearch = useCallback(async (q: string) => {
    if (!q.trim()) return;
    setLoading(true);
    setSearched(true);
    try {
      const r = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
      const data = await r.json();
      setHits(data.hits || []);
    } catch {
      setHits([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (initialQuery) doSearch(initialQuery);
  }, [initialQuery, doSearch]);

  const getTagFromLine = (text: string) => {
    const m = text.match(/^\- \[(stated|ingested|derived)\]/);
    return m ? m[1] : null;
  };

  const handleHitClick = (hit: SearchHit) => {
    const name = hit.file.split('/').pop()?.replace('.md', '') || '';
    onSelectFile({
      name,
      path: hit.file,
      category: hit.category,
      description: '',
      sensitivity: 'private',
      factCount: 0,
      sources: [],
    });
  };

  return (
    <div className="p-4 lg:p-6 max-w-4xl">
      <h2 className="text-lg font-semibold mb-4">Search Vault</h2>
      <div className="flex gap-2 mb-4">
        <div className="relative flex-1">
          <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search facts, names, descriptions..."
            className="pl-9"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && doSearch(query)}
            autoFocus
          />
        </div>
        <Button onClick={() => doSearch(query)} disabled={loading || !query.trim()}>
          {loading && <Loader2 className="h-4 w-4 animate-spin mr-1" />}
          Search
        </Button>
      </div>

      {searched && !loading && hits.length === 0 && (
        <div className="flex flex-col items-center py-12 text-muted-foreground">
          <AlertCircle className="h-8 w-8 mb-2" />
          <p className="text-sm">No matches for &ldquo;{query}&rdquo;</p>
          <p className="text-xs mt-1">An empty result is information, not a failure</p>
        </div>
      )}

      {hits.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs text-muted-foreground mb-2">
            {hits.length} result{hits.length !== 1 ? 's' : ''}
          </p>
          {hits.map((hit, i) => {
            const tag = getTagFromLine(hit.text);
            return (
              <Card
                key={`${hit.file}-${hit.line}-${i}`}
                className="cursor-pointer hover:bg-muted/50 transition-colors"
                onClick={() => handleHitClick(hit)}
              >
                <CardContent className="p-3 flex gap-3">
                  <div className="shrink-0">
                    {tag && (
                      <Badge className={`text-[9px] ${TAG_COLORS[tag] || ''}`} variant="secondary">
                        {tag}
                      </Badge>
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-mono leading-relaxed break-all">
                      {hit.text}
                    </p>
                    <p className="text-[10px] text-muted-foreground mt-1">
                      {hit.file}:{hit.line}
                    </p>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
}
