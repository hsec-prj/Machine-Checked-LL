"""Check the generic roots, the hydrated proof roots, or compile both hydrated CLIs."""
import argparse
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('core', 'full', 'native'))
    parser.add_argument('--artifact', type=Path, required=True)
    parser.add_argument('--library-file', type=Path, help='Agda library registry listing standard-library-2.3')
    args = parser.parse_args()
    artifact = args.artifact.resolve()
    src = artifact / 'src'
    base = ['agda', '--no-default-libraries', '--without-K']
    if args.library_file:
        base.append('--library-file=' + str(args.library_file.resolve()))
    safe = base + ['--safe', '-W', 'error']
    if args.phase == 'native':
        for directory, main_module in (('extract', 'Main.agda'), ('graph-cli', 'RunCycSAT.agda')):
            subprocess.run(base + ['--compile', '--compile-dir=_bin', main_module],
                           cwd=artifact / 'experiments' / directory, check=True)
        return
    if args.phase == 'core':
        subprocess.run(safe + ['-l', 'standard-library-2.3', '-i', str(src), '-i', str(HERE), 'CoreOnly.agda'],
                       cwd=HERE, check=True)
    else:
        subprocess.run(safe + ['Everything.agda'], cwd=src, check=True)
    subprocess.run(safe + ['Everything.agda'], cwd=src / 'graph', check=True)


if __name__ == '__main__':
    main()
