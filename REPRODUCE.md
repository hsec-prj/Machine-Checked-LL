# Reproducing proofs, tables and measurements

Extract the ZIP in an empty directory. Run the following from the extracted artifact directory. Use Python 3.11 or newer. The kernel checks require Agda 2.8.0 and standard-library 2.3 registered with Agda. The native programs additionally require GHC. If needed, pass the registry path with `--library-file` to each Agda check. Local installation details for Yosys, ABC and OpenSTA must match the tool pins when comparing archived bytes or physical results. Use fresh sibling paths for each run.

## Before fetching circuits

```sh
shasum -a 256 -c SHA256SUMS
python3 -B experiments/analysis/replay_tables.py ../tables
python3 -B rebuild/agda/check.py core --artifact .
```

The table reader regenerates 13 TeX files and checks their digests. It also reconstructs 327 P53 rows from projected scalar records. Timing, memory, historical inconclusive outcomes and solver records describe the original runs. See [table coverage](experiments/data/TABLE-DATA.md).

## Rebuild local proof instances

The ZIP excludes ISCAS’85 circuit derivatives. Acquire the pinned sources directly from the upstream repositories. An existing authorized cache with the same pinned bytes can be used offline. The source URLs, digest checks, Yosys/ABC conversion rules, archived header convention and the local receipt are described in the [input instructions](rebuild/inputs/README.md).

```sh
python3 -B rebuild/inputs/inputs.py fetch --cache ../cache
python3 -B rebuild/inputs/inputs.py build --release . --cache ../cache --output ../overlay
python3 -B rebuild/agda/generate.py --artifact . --rtl ../cache/v/c17.v --norm ../overlay/experiments/data/configured/norm/c17.bench --literals ../overlay/experiments/data/benchmarks/iscas85 --output ../modules
mkdir ../hydrated
cp -R . ../hydrated/
cp -R ../overlay/experiments/. ../hydrated/experiments/
cp -R ../modules/. ../hydrated/src/
cd ../hydrated
python3 -B rebuild/agda/check.py full --artifact .
python3 -B rebuild/agda/check.py native --artifact .
```

The hydrated tree contains the local circuit data. Preserve the original ZIP separately. The full proof command checks both Agda libraries. The IO front ends are compiled separately from the safe proof roots.

## Repeat measurements from the hydrated directory

```sh
python3 -B rebuild/configured.py --main experiments/extract/_bin/Main --rtl ../cache/v/c17.v --max-width 10
python3 -B rebuild/ppa_inputs.py
python3 -B experiments/analysis/power_revision.py --lib "$NANGATE_LIB" --output ../ppa --tsv ../ppa.tsv
python3 -B rebuild/compare_ppa.py ../ppa.tsv ../ppa
```

The reader regenerates the 108 Tier E designs and checks every emitted BENCH hash. The width argument sets the ceiling for exhaustive comparison against the archived counters. Above the ceiling the reader checks 256 deterministic input/key vectors per design, including planted-key and Hamming-sphere cases. A further output-inverted run exercises the failure detector. Compute cost grows with the square of the input-space size. For P44, set NANGATE_LIB to the separately obtained Nangate45 Liberty with SHA-256 2efd0b32eb580e4e60e72fc0575bb3bc69aac907c91d908442e4ae6d7fe55895. The flow verifies the seven-by-three input population and records the per-cell equivalence controls and physical results. [Library source and terms](docs/THIRD-PARTY.md)

## Replay the prescribed Tier X keys and historical S4 samples

Start in the hydrated directory after compiling Main. Tier X needs the CUDD 3.0 shared library. Set `CUDD_LIB` to its installed path. S4 uses Python's seeded generator, the scalar simulator, Main and yosys-abc. The seeds, sample budgets, check positions and prescribed synthetic keys are included in this ZIP. The commands generate the tested circuits locally and compare their digests before validating the observations. Choose new result filenames.

```sh
python3 -B rebuild/replay/tier_x.py --main experiments/extract/_bin/Main --lib "$CUDD_LIB" --output ../tier-x.json
python3 -B rebuild/replay/s4.py --main experiments/extract/_bin/Main --rtl ../cache/v/c17.v --out ../s4.json
```

Tier X checks the exact set of differing data inputs for each prescribed key and counts its size using decision diagrams. S4 regenerates the random and targeted vectors in their historical order, then cross-checks selected positions with scalar evaluation. The receipts report observations from these runs. Historical timings and memory use are available in the archived records.

## Replay the remaining Tier S checks and Tier M compiler controls

From the hydrated directory run

```sh
python3 -B rebuild/replay/sm_replay.py --main experiments/extract/_bin/Main --rtl ../cache/v/c17.v --out ../sm-results.json
```

The reader uses the public test configurations, reconstructed local circuits and Berkeley ABC. Use the pinned Yosys/ABC build to compare solver verdicts and diagnostic counts. Choose a new output path. To repeat a single host, add `--host c7552`. The c6288 arithmetic reference check also requires a local C compiler.

There are 22 configurations with five S checks each and 33 M configurations with two checks each. Compare the observed status of each test with its historical expectation. An intentional failure of a mutation check can match the reference. For the two c7552 control configurations, the receipt distinguishes the first attempt from the retry used in the paper. The counted population contains 176 rows. The two superseded attempts bring the number of executions to 178. Timing is recorded for the current machine.

## Compare the historical P41, P43 and paired observations

Run these commands from the hydrated directory. Choose new output paths.

```sh
python3 -B rebuild/replay/history_functional.py --main experiments/extract/_bin/Main --out ../functional.json
python3 -B rebuild/replay/paired_functional.py --output ../paired.json
python3 -B rebuild/replay/history_compare.py --functional ../functional.json --paired ../paired.json --output ../comparison.tsv
```

The 358-row comparison identifies each historical observation and the scope of its fresh test. For P41 and P43 it checks the standalone comparator and samples the reconstructed host outputs against a fingerprint of the original circuit evaluated at the recorded test key. For the paired study it checks data-only functions and compares the sampled output with a fingerprint for each of the two original routes. The paired equivalence and inversion controls use reconstructed host functions with data inputs only.

The historical status, iteration count, elapsed time and classification columns describe the recorded campaign. The archival recount uses scalar observations projected from its logs. The five P43 rows classified as timeouts have no terminal solver record. The fresh measurements use known test inputs. New solver recovery, DIP counts and timing are outside their scope. The full historical circuit digests identify the preserved author-side files.

### Paired-run003 reproduction scope

Each count below covers c6288, c1355, c5315 and c7552. The [16-row checksum table](rebuild/replay/paired-file-identities.tsv) lists four roles per host covering one ordinary compiler output, one historical structure and two final run003 inputs. The flattened host inputs, standalone comparators and key-free reference circuits have separate checks.

| File or measurement | Reader procedure | Historical comparison |
|---|---|---|
| Flattened host input and ordinary compiler output (`native_output`) | Rebuild from the pinned external inputs and run `paired_bytes.py` with the compiled Main. | 4/4 flat inputs and 4/4 native outputs matched by SHA-256. |
| Standalone comparator used by the splice route | The same command generates and measures the comparator for each host width. | 4/4 matched by length and SHA-256. |
| Key-free single-output reference | Run `measure.py` as described below. Its receipt records both the fresh ABC header and the result of restoring the archived comment. | 4/4 bodies matched. Whole-file matches were 0/4 with fresh comments and 4/4 with restored comments. |
| Earlier structure (`historical_structure`) | Supply an existing file to `check_paired_files.py` for a length and SHA-256 comparison. | Author archive matches 4/4. Independent reader regenerations 0/4. |
| Final run003 inputs (`run003_certified` and `run003_splice`) | Use the same supplied-file check for each host and route. | Author archive matches 8/8. Independent reader regenerations 0/8. |

From the hydrated directory with a freshly compiled Main, run

```sh
python3 -B rebuild/replay/paired_bytes.py --output ../paired-bytes.json
```

For each host, the certified row measures the ordinary native compiler output using the general ITC regression fixture. The splice row measures the standalone comparator. Each final digest is cross-checked against the historical processed table. The optional `--final HOST ROUTE FILE` checks a supplied final file. Without it, that row’s final status is `unchecked`. The known-key functional comparisons in the preceding section measure behavior on the specified inputs.

The historical paired input producer had SHA-256 `f55398b42a104836765a30ef90ce7e91222ff0adadfdc625c82b02e5853322e9`. The later producer in the author archive had SHA-256 `7cac13b4773b72131cb6bd278e989c6dfb912d1d1bf1d081e5c8be3d35a58354`. The run003 manifest identifies the solver that consumed the inputs by SHA-256 `2829b7bb49097eb886c51fcafcdf2041fa71303aefbea78f908cfab4ca6240d7`.

### Measure the four single-output reference circuits

From the hydrated directory with standalone Berkeley ABC on PATH, run

```sh
python3 -B rebuild/reference/measure.py --output ../reference-hashes.json
```

The four key-free outputs use the August 26 analysis converter in `rebuild/reference/lut2gate.py` (Git commit `5aea020e21`, SHA-256 `256dfa184670448f5edf463896848b3e0dc5e3d98a3568b8847593e71544dd0b`). The general regression converter is in `experiments/scripts/lut2gate.py`. The receipt records each regenerated reference's full SHA-256 and the SHA-256 from the byte after the first LF through EOF. The `reference` entry records the file with ABC’s fresh first-line comment. The `restored_reference` entry records the same generated body with the historical first line from `rebuild/reference/abc-comments.json`. Each comment preserves the original benchmark path and timestamp as text. CEC compares the generated LUT and restored gate representations.

### Identify a local file at a specific stage

The table `rebuild/replay/paired-file-identities.tsv` records byte length and full SHA-256 for four objects per host. The roles are `native_output` (ordinary compiler output), `historical_structure` (earlier structure recorded as a run003 input), and the two final inputs `run003_certified` and `run003_splice`. The checker only reads supplied files and works from the extracted ZIP with Python.

```sh
python3 -B rebuild/replay/check_paired_files.py
python3 -B rebuild/replay/check_paired_files.py --file c1355 historical_structure /path/to/local-file
```

Repeat `--file HOST ROLE FILE` for additional rows or use `--output FILE` to save JSON to a new path. Omitted rows are `unchecked`. Running the checker without any files returns 16 unchecked rows and exit code 0. Supplied files with the expected length and SHA-256 are `match`. A differing length or digest gives `mismatch` and exit code 1. An invalid explicit path, host or role is an invocation error. A match identifies the bytes supplied. A claim of independent regeneration also requires a record of producing those bytes from the ZIP and the pinned external inputs.
