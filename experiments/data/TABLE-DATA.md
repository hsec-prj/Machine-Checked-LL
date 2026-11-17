# Reproducing the published tables

Run this command from the artifact root and choose a new output directory outside the artifact.

```sh
python3 -B experiments/analysis/replay_tables.py ../replayed-tables
```

The reader reconstructs all 327 rows, including retries, of the historical configured-validation TSV and checks them byte for byte against `processed/p53-iscas-configured.tsv`. It also renders thirteen historical TeX files from ten processed TSVs and three fixture TSVs and checks their SHA-256 digests. Appendix B's configured tables share one TeX file. These checks reproduce the analysis of recorded runs. New measurements require the corresponding inputs and tools.

The five indexes in `p53-facts/` preserve row order and link to derived records by relative attempt identifiers. The 530 JSON projections preserve measurement values, outcomes, control names, selected executable and circuit digests, and mutation counts. Mutation counts come from the lengths of the recorded edit lists. A digest identifies the original bytes for comparison. The projections omit gate edits, netlist content, raw logs, command lines and machine-specific paths. Each projected file derives from the same relative record under the archival P53 data. Historical fixtures and processed TSVs retain experimental parameters and outcomes, which include synthetic test keys and logical provenance filenames. Paths embedded in historical table captions and TSV cells identify the original study layout. They need not resolve in this distribution.

The thirteen reference digests in `table-output-sha256.json` were obtained by running the original table programs against the prior export with SHA-256 `446636cf761fa5c84d78251347e747a9c5fc4ed97844c92738c04f92cfae94cc`. Its standard manuscript comparison checks seven TeX files. The audit also verified the complete controls table (Table 5) against the manuscript.
