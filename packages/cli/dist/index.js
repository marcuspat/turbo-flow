#!/usr/bin/env node
// ─── turbo-flow CLI ──────────────────────────────────
import { Command } from 'commander';
import { init } from './cli/init.js';
import { runCommand } from './cli/run.js';
import { statusCommand } from './cli/status.js';
import { answerCommand } from './cli/answer.js';
import { abortCommand } from './cli/abort.js';
import { doctorCommand } from './cli/doctor.js';
import { newCommand } from './cli/new.js';
import { adoptCommand } from './cli/adopt.js';
const VERSION = '5.0.0-alpha.1';
const program = new Command()
    .name('turbo-flow')
    .description('The agentic harness — write a spec, a bounded graph of agents runs it unattended.')
    .version(VERSION);
program
    .command('init')
    .description('Scaffold the harness into the current repo')
    .option('--devcontainer', 'Include devcontainer profile')
    .option('--profile <name>', 'Install an optional profile (e.g. ruv)')
    .action(async (opts) => {
    try {
        await init(opts);
    }
    catch (e) {
        console.error(`turbo-flow init failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('new <slug>')
    .description('Create a new spec from the template')
    .action(async (slug) => {
    try {
        await newCommand(slug);
    }
    catch (e) {
        console.error(`turbo-flow new failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('run <spec-id>')
    .description('Run a spec through the graph')
    .option('--step', 'Run exactly one node iteration, then exit')
    .option('--resume', 'Resume an existing run')
    .option('--budget <usd>', 'Override the run budget')
    .action(async (specId, opts) => {
    try {
        await runCommand(specId, opts);
    }
    catch (e) {
        console.error(`turbo-flow run failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('step <spec-id>')
    .description('Run exactly one node iteration')
    .action(async (specId) => {
    try {
        await runCommand(specId, { step: true });
    }
    catch (e) {
        console.error(`turbo-flow step failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('status [spec-id]')
    .description('Show run state (all runs or specific spec)')
    .action(async (specId) => {
    try {
        await statusCommand(specId);
    }
    catch (e) {
        console.error(`turbo-flow status failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('answer <spec-id> <answer>')
    .description('Record a human decision and unblock a run')
    .action(async (specId, answer) => {
    try {
        await answerCommand(specId, answer);
    }
    catch (e) {
        console.error(`turbo-flow answer failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('abort <spec-id> [reason]')
    .description('Halt a run')
    .action(async (specId, reason) => {
    try {
        await abortCommand(specId, reason);
    }
    catch (e) {
        console.error(`turbo-flow abort failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('doctor')
    .description('Check dependencies and repo wiring')
    .action(async () => {
    try {
        await doctorCommand();
    }
    catch (e) {
        console.error(`turbo-flow doctor failed: ${e.message}`);
        process.exit(1);
    }
});
program
    .command('adopt')
    .description('Compile contract/source.md into CLAUDE.md')
    .option('--output <path>', 'Output path (default: CLAUDE.md)')
    .action(async (opts) => {
    try {
        await adoptCommand(opts);
    }
    catch (e) {
        console.error(`turbo-flow adopt failed: ${e.message}`);
        process.exit(1);
    }
});
program.parse();
//# sourceMappingURL=index.js.map