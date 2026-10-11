"""Separate runners for kit jobs: Claude transcript import and opt-in codex exec.

The orchestrator dispatches Claude jobs itself with prompt/model/effort/images and the reply
schema. This adapter only reads its SubagentHandback. Codex runs in a read-only scratch root.
"""
import argparse
import json
import subprocess
import time
from pathlib import Path

from . import accounting, loop, paths, transcripts
from .kit import outside_repo


def destination(run, job):
    return paths.job_path(run, job, 'replies')


def claude(run, job_path, transcript):
    job = loop.load(job_path)
    target = destination(run, job)
    paths.job_path(run, job, 'costs')
    loop.save(target, transcripts.extract(transcript))
    accounting.record(run, job, transcript)
    return target


def codex_command(job, schema_path, reply_path, scratch):
    command = ['codex', 'exec', '--json', '--ephemeral', '--sandbox', 'read-only',
               '--skip-git-repo-check', '--cd', str(scratch), '--model', job['model'],
               '--config', 'model_reasoning_effort=' + json.dumps(job['effort']),
               '--output-schema', str(schema_path), '--output-last-message', str(reply_path)]
    for path in job['images']:
        command += ['--image', path]
    return command + ['-']


def codex(run, job_path, out):
    job = loop.load(job_path)
    target = destination(run, job)
    paths.job_path(run, job, 'costs')
    scratch = paths.job_path(outside_repo(out), job, 'scratch')
    scratch.mkdir(parents=True, exist_ok=False)
    schema_path, reply_path, log = [paths.contained(scratch, name) for name in
                                   ('schema.json', 'reply.json', 'codex.jsonl')]
    loop.save(schema_path, job['reply_schema'])
    command = codex_command(job, schema_path, reply_path, scratch)
    start = time.monotonic()
    with log.open('w') as stdout, paths.contained(scratch, 'stderr.txt').open('w') as stderr:
        result = subprocess.run(command, input=job['prompt'], text=True, stdout=stdout, stderr=stderr, check=False)
    accounting.record(run, job, log, elapsed=time.monotonic() - start)
    if result.returncode:
        raise RuntimeError(f'codex exec exited {result.returncode}; see {scratch / "stderr.txt"}')
    target = destination(run, job)
    # Keep malformed replies for the kit to return to the agent once.
    loop.write_atomic(target, reply_path.read_text())
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', required=True, type=Path)
    commands = parser.add_subparsers(dest='runner', required=True)
    claude_parser = commands.add_parser('claude')
    claude_parser.add_argument('job', type=Path)
    claude_parser.add_argument('transcript', type=Path)
    codex_parser = commands.add_parser('codex')
    codex_parser.add_argument('job', type=Path)
    codex_parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    if args.runner == 'claude':
        print(claude(args.run, args.job, args.transcript))
    else:
        print(codex(args.run, args.job, args.out))


if __name__ == '__main__':
    main()
