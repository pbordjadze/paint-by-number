"""loop new/draw/jobs/collect/decide/replay/report and review/calibration tools."""
import argparse
import json
import os
from pathlib import Path

from . import accounting, calibration, kit, loop, pages


def report(run):
    run = Path(run)
    decisions = [loop.load(p) for p in sorted(run.glob('rounds/*/decision.json'))]
    if (run / 'decision.json').exists():
        decisions.append(loop.load(run / 'decision.json'))
    for decision in decisions:
        if isinstance(decision, dict) and 'standings' in decision:
            decision.update(loop.favorites(decision['standings'], 'vetoed'))
        elif isinstance(decision, list):
            for result in decision:
                result.update(loop.favorites(result['standings']))
    return {'standings': decisions, 'ledger': loop.load(run / 'ledger.json', {'rounds': []}),
            'costs': accounting.report(run)}


def main(argv=None):
    parser = argparse.ArgumentParser(prog='loop', description=__doc__)
    parser.add_argument('--run', type=Path, default=os.environ.get('LOOP_RUN'), help='run record directory')
    parser.add_argument('--out', type=Path, default=Path(os.environ.get('FACTORY_OUT', '/root/factory-out')) / 'loop',
                        help='render/scratch output, outside the repo')
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('new')
    create.add_argument('piece', help='piece ID under factory/pieces, or a directory containing piece.toml')
    create.add_argument('--calibration', type=Path)
    for command in ('draw', 'jobs', 'collect', 'decide'):
        commands.add_parser(command).add_argument('round', type=int)
    commands.add_parser('replay')
    commands.add_parser('report')
    for command in ('checkpoint', 'gallery'):
        review = commands.add_parser(command)
        review.add_argument('--round', type=int, default=1)
        review.add_argument('--picks', type=Path)
    calibrate = commands.add_parser('calibrate')
    calibrate.add_argument('picks', type=Path)
    args = parser.parse_args(argv)
    if args.run is None:
        parser.error('provide --run or LOOP_RUN')
    try:
        if args.command == 'new':
            piece = Path(args.piece)
            if not piece.is_dir():
                piece = loop.REPO / 'factory/pieces' / args.piece
            result = kit.new(piece, args.run, args.calibration)
        elif args.command in ('draw', 'jobs', 'collect', 'decide'):
            result = getattr(kit.Run(args.run, args.out), args.command)(args.round)
        elif args.command == 'replay':
            result = {'replayed': str(kit.replay(args.run, args.out))}
        elif args.command == 'report':
            result = report(args.run)
        elif args.command == 'calibrate':
            result = calibration.calculate(args.run, args.picks, kit.outside_repo(args.out) / 'calibration.json')
        else:
            result = {'page': str(pages.generate(args.run, kit.outside_repo(args.out) / f'{args.command}.html',
                      n=args.round, checkpoint=args.picks, gallery=args.command == 'gallery'))}
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f'loop: {error}\n')
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if args.command == 'collect' and any(s != 'accepted' for s in result.values()):
        return 1
    return 0
