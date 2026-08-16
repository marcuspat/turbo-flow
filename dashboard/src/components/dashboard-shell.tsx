"use client";

import React, { useState, useEffect, useCallback } from 'react';
import {
  Brain, Search, FileText, Inbox, Activity, Shield, Zap, Waves,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { VaultBrowser } from './views/vault-browser';
import { SearchView } from './views/search-view';
import { CaptureView } from './views/capture-view';
import { IntakeView } from './views/intake-view';
import { WavesView } from './views/waves-view';
import { DoctorView } from './views/doctor-view';

export interface VaultFile {
  name: string;
  path: string;
  category: string;
  description: string;
  sensitivity: 'private' | 'shareable' | 'public';
  factCount: number;
  sources: string[];
}

export interface ParsedFile {
  frontmatter: {
    name: string;
    description: string;
    sources: string[];
    sensitivity: string;
    aliases?: string[];
  };
  facts: { tag: string; fact: string; line: number }[];
  relatedLinks: string[];
  raw: string;
}

type View = 'browser' | 'search' | 'capture' | 'intake' | 'waves' | 'doctor';

const NAV_ITEMS: { id: View; label: string; icon: React.ReactNode }[] = [
  { id: 'browser', label: 'Vault', icon: <Brain className="h-4 w-4" /> },
  { id: 'search', label: 'Search', icon: <Search className="h-4 w-4" /> },
  { id: 'capture', label: 'Capture', icon: <Zap className="h-4 w-4" /> },
  { id: 'intake', label: 'Intake', icon: <Inbox className="h-4 w-4" /> },
  { id: 'waves', label: 'Waves', icon: <Waves className="h-4 w-4" /> },
  { id: 'doctor', label: 'Doctor', icon: <Shield className="h-4 w-4" /> },
];

export function DashboardShell() {
  const [activeView, setActiveView] = useState<View>('browser');
  const [selectedFile, setSelectedFile] = useState<VaultFile | null>(null);
  const [parsedFile, setParsedFile] = useState<ParsedFile | null>(null);
  const [fileDialogOpen, setFileDialogOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [doctorData, setDoctorData] = useState<Record<string, unknown> | null>(null);

  const refreshDoctor = useCallback(async () => {
    try {
      const r = await fetch('/api/doctor');
      if (r.ok) setDoctorData(await r.json());
    } catch { /* silent */ }
  }, []);

  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        const r = await fetch('/api/doctor');
        if (r.ok && active) setDoctorData(await r.json());
      } catch { /* silent */ }
    };
    load();
    const interval = setInterval(load, 30000);
    return () => { active = false; clearInterval(interval); };
  }, []);

  const openFile = async (file: VaultFile) => {
    setSelectedFile(file);
    setFileDialogOpen(true);
    try {
      const r = await fetch(`/api/facts?name=${encodeURIComponent(file.name)}`);
      if (r.ok) setParsedFile(await r.json());
    } catch {
      setParsedFile(null);
    }
  };

  const totalFacts = (doctorData?.vault as Record<string, unknown>)?.totalFacts as number ?? 0;
  const intakeCount = (doctorData?.intake as Record<string, unknown>)?.undistilled as number ?? 0;
  const lintOk = (doctorData?.lint as Record<string, unknown>)?.passed as boolean;

  return (
    <div className="flex h-screen overflow-hidden">
      {/* Sidebar */}
      <aside className="w-56 border-r bg-sidebar-background flex flex-col shrink-0">
        <div className="p-4 flex items-center gap-2.5">
          <div className="h-8 w-8 rounded-lg bg-primary flex items-center justify-center">
            <Brain className="h-4 w-4 text-primary-foreground" />
          </div>
          <div>
            <h1 className="text-sm font-semibold tracking-tight">Turbo Brain</h1>
            <p className="text-[11px] text-muted-foreground">context vault</p>
          </div>
        </div>
        <Separator />
        <nav className="flex-1 p-2 space-y-0.5">
          {NAV_ITEMS.map((item) => (
            <Button
              key={item.id}
              variant={activeView === item.id ? 'secondary' : 'ghost'}
              className="w-full justify-start gap-2 text-sm h-8"
              onClick={() => setActiveView(item.id)}
            >
              {item.icon}
              {item.label}
              {item.id === 'intake' && intakeCount > 0 && (
                <Badge variant="default" className="ml-auto text-[10px] px-1.5 h-4 bg-primary">
                  {intakeCount}
                </Badge>
              )}
            </Button>
          ))}
        </nav>
        <div className="p-3 border-t">
          <div className="flex items-center justify-between text-xs text-muted-foreground mb-1.5">
            <span>{totalFacts} facts</span>
            <span className={lintOk ? 'text-emerald-600' : 'text-destructive'}>
              {lintOk ? 'lint ok' : 'lint err'}
            </span>
          </div>
          <div className="flex items-center justify-between text-xs text-muted-foreground">
            <span>plain files in git</span>
            <Activity className="h-3 w-3 text-emerald-500" />
          </div>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 flex flex-col min-w-0">
        {/* Top bar with search */}
        <header className="h-12 border-b flex items-center px-4 gap-3 shrink-0">
          <div className="relative flex-1 max-w-sm">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
            <Input
              placeholder="Search vault... (Ctrl+K)"
              className="pl-8 h-8 text-sm"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && searchQuery.trim()) {
                  setActiveView('search');
                }
              }}
            />
          </div>
          <Badge variant="outline" className="text-[10px] font-normal">
            v0.2.0
          </Badge>
        </header>

        {/* View content */}
        <div className="flex-1 overflow-auto">
          {activeView === 'browser' && (
            <VaultBrowser onSelectFile={openFile} />
          )}
          {activeView === 'search' && (
            <SearchView initialQuery={searchQuery} onSelectFile={openFile} />
          )}
          {activeView === 'capture' && <CaptureView />}
          {activeView === 'intake' && <IntakeView />}
          {activeView === 'waves' && <WavesView />}
          {activeView === 'doctor' && <DoctorView data={doctorData} onRefresh={refreshDoctor} />}
        </div>
      </main>

      {/* File detail dialog */}
      <Dialog open={fileDialogOpen} onOpenChange={setFileDialogOpen}>
        <DialogContent className="max-w-2xl max-h-[80vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              {selectedFile?.name}
              <Badge variant="outline" className="text-[10px]">
                {selectedFile?.category}/{selectedFile?.name}.md
              </Badge>
              <Badge
                variant={selectedFile?.sensitivity === 'private' ? 'destructive' :
                  selectedFile?.sensitivity === 'shareable' ? 'default' : 'secondary'}
                className="text-[10px]"
              >
                {selectedFile?.sensitivity}
              </Badge>
            </DialogTitle>
          </DialogHeader>
          {parsedFile && (
            <ScrollArea className="flex-1 -mx-6 px-6">
              <div className="space-y-3 pb-4">
                <p className="text-sm text-muted-foreground">
                  {parsedFile.frontmatter.description}
                </p>
                {parsedFile.frontmatter.sources.length > 0 && (
                  <div className="flex gap-1.5 flex-wrap">
                    {parsedFile.frontmatter.sources.map((s) => (
                      <Badge key={s} variant="outline" className="text-[10px]">{s}</Badge>
                    ))}
                  </div>
                )}
                <Separator />
                <div className="space-y-1.5">
                  {parsedFile.facts.map((f, i) => (
                    <div
                      key={i}
                      className="flex gap-2 text-sm py-1 px-2 rounded-md hover:bg-muted/50"
                    >
                      <Badge
                        variant={
                          f.tag === 'stated' ? 'default' :
                          f.tag === 'ingested' ? 'secondary' : 'outline'
                        }
                        className="shrink-0 text-[10px] mt-0.5 h-5"
                      >
                        {f.tag}
                      </Badge>
                      <span className="text-foreground/90 leading-relaxed">{f.fact}</span>
                    </div>
                  ))}
                </div>
                {parsedFile.relatedLinks.length > 0 && (
                  <>
                    <Separator />
                    <div className="flex gap-1.5 flex-wrap">
                      <span className="text-xs text-muted-foreground">Related:</span>
                      {parsedFile.relatedLinks.map((l) => (
                        <Badge key={l} variant="outline" className="text-[10px]">[[{l}]]</Badge>
                      ))}
                    </div>
                  </>
                )}
              </div>
            </ScrollArea>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}