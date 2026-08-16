"""Turbo Brain adapter interface.

Adapters bring external data into the vault as intake files.
Each adapter: reads from a source, writes [ingested] facts to intake/<source>/.

Contract:
  - Input: source config (from .turbo-brain.toml or CLI args)
  - Output: markdown files in intake/<source>/ with [ingested] tags and (src: ...)
  - Zero LLM usage — adapters are mechanical extractors
  - Idempotent — running twice produces the same files
  - Content-identity keys, never timestamp keys (per ruflo ADR importer)
"""

from abc import ABC, abstractmethod
from typing import List, Dict, Optional


class BaseAdapter(ABC):
    """Base class for all Turbo Brain adapters."""

    name: str = "base"
    description: str = ""

    @abstractmethod
    def fetch(self) -> List[Dict]:
        """Fetch raw records from the source.

        Returns list of dicts with at least:
          - id: content-identity key (never timestamp)
          - content: text to extract facts from
          - captured_at: ISO 8601 observation time
        """
        ...

    @abstractmethod
    def extract(self, record: Dict) -> List[str]:
        """Extract fact lines from a single record.

        Returns list of "- [ingested] fact (src: {name} {date})" lines.
        """
        ...

    def run(self, intake_path: str, dry_run: bool = False) -> Dict:
        """Full adapter run: fetch -> extract -> write intake files.

        Returns summary dict with counts and any errors.
        """
        import os
        from datetime import datetime, timezone

        out_dir = os.path.join(intake_path, self.name)
        os.makedirs(out_dir, exist_ok=True)

        records = self.fetch()
        written = 0
        errors = []

        for record in records:
            try:
                facts = self.extract(record)
                if not facts:
                    continue

                filename = f"{record['id']}.md"
                filepath = os.path.join(out_dir, filename)
                content = f"---\nname: {record['id']}\n"
                content += f"description: {self.name} adapter capture\n"
                content += f"sources: [{self.name}]\n"
                content += "sensitivity: private\n---\n"
                content += "\n".join(facts)
                content += f"\n- Related: [[{self.name}]]\n"

                if dry_run:
                    written += 1
                    continue

                with open(filepath, "w") as f:
                    f.write(content)
                written += 1
            except Exception as e:
                errors.append({"id": record.get("id", "unknown"), "error": str(e)})

        return {
            "adapter": self.name,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "fetched": len(records),
            "written": written,
            "errors": errors,
            "dry_run": dry_run,
        }


class RunLedgerAdapter(BaseAdapter):
    """Adapter for Turbo Flow run ledgers (.lg/runs/*/state.json).

    Reads run state JSON files and extracts project distillate as [ingested] facts.
    """
    name = "ledger"
    description = "Turbo Flow run ledger adapter"

    def __init__(self, ledger_path: Optional[str] = None):
        self.ledger_path = ledger_path

    def fetch(self) -> List[Dict]:
        import os, json, glob
        records = []
        base = self.ledger_path or os.path.expanduser("~/.lg/runs")
        if not os.path.isdir(base):
            return records
        for state_file in sorted(glob.glob(os.path.join(base, "*/state.json"))):
            try:
                with open(state_file, "r") as f:
                    data = json.load(f)
                run_id = os.path.basename(os.path.dirname(state_file))
                records.append({
                    "id": f"run-{run_id}",
                    "content": json.dumps(data),
                    "captured_at": data.get("timestamp", data.get("started_at", "")),
                    "data": data,
                })
            except (OSError, json.JSONDecodeError):
                continue
        return records

    def extract(self, record: Dict) -> List[str]:
        data = record.get("data", {})
        date = record["captured_at"][:10] if record.get("captured_at") else "unknown"
        facts = []
        repo = data.get("repo", data.get("project", "unknown"))
        status = data.get("status", data.get("verdict", "unknown"))
        facts.append(f"- [ingested] Run {record['id']}: {repo} -> {status} (src: ledger {date})")
        plan = data.get("plan", {})
        if isinstance(plan, dict) and plan.get("steps"):
            facts.append(f"- [ingested] {repo} plan had {len(plan['steps'])} steps (src: ledger {date})")
        budget = data.get("budget_spent", data.get("spend", 0))
        if budget:
            facts.append(f"- [ingested] {repo} spent ${budget:.4f} on run (src: ledger {date})")
        error = data.get("error", data.get("failure_reason", ""))
        if error:
            facts.append(f"- [ingested] {repo} run failed: {str(error)[:200]} (src: ledger {date})")
        return facts


__all__ = ["BaseAdapter", "RunLedgerAdapter"]
