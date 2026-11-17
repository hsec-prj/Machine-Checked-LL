# Machine-Checked Observation Separation for Logic Locks

This reproduction package contains the general Agda proofs, a reader-side reconstruction of the benchmark instances, archived numerical results, and programs for regenerating the paper's tables and repeating selected measurements. The ZIP excludes ISCAS’85 circuit derivatives. Readers obtain the pinned upstream sources and generate the benchmark circuits and eight ISCAS-specific Agda modules locally. The public archive includes the ITC’99 corresponding sources for its retained ITC derivatives.

Readers can check the Agda proofs, regenerate the paper’s tables from the archived data, and rerun the selected functional and physical measurements listed in the reproduction instructions. P41 and P43 readers can compare fresh host outputs with the archived known-key fingerprints. The reported solver outcomes and timings come from the original campaigns.

## What readers can reproduce for paired-run003

The paired study covers c6288, c1355, c5315 and c7552. With the pinned external sources and local tools, readers can reproduce the four flattened host inputs, four ordinary compiler outputs and four standalone comparators byte for byte. For the four key-free, single-output reference circuits, the generated bodies match the historical bodies. Restoring the archived first-line ABC comments also recovers the four historical whole-file hashes.

For whole-file verification of the four historical structures and eight final run003 inputs, the ZIP provides reference checksums. The checker compares a file supplied by the reader with its recorded length and SHA-256. Independent regeneration from the ZIP has been demonstrated for 0/4 historical structures and 0/8 final inputs. [Commands and scope by file role](REPRODUCE.md#paired-run003-reproduction-scope)

[Reproduction instructions](REPRODUCE.md) · [Software and data licenses](LICENSE) · [Third-party notices](docs/THIRD-PARTY.md) · [Scope of the archived table data](experiments/data/TABLE-DATA.md)
