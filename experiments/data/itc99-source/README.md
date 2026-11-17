# ITC’99 circuit sources and structural replay

This directory supplies the editable RTL for all six hosts supported by the
artifact's ITC’99 preparation command. The original Torino VHDL is in
`polito/`. The CCSL Verilog translations used as synthesis inputs are in
`ccsl/`. Both sets are byte-for-byte copies from the revisions below. In the
original repository each VHDL file is at `i99t/<host>/<host>.vhd`. The Verilog
files are at the translation repository's root. [Checksums of the twelve upstream files](SHA256SUMS)

| Source | Revision and terms |
|---|---|
| Politecnico di Torino CAD Group, I99T | [Upstream files and attribution](https://github.com/cad-polito-it/I99T/tree/8a2c3b500ee7ff20e7031de92592b737bedc6d8c), [EUPL 1.2](../../../docs/licenses/EUPL-1.2.txt) |
| CCSL, University of the Aegean, ITC99-RTL-Verilog | [Upstream files and conversion description](https://github.com/ccsl-uaegean/ITC99-RTL-Verilog/tree/8e6a23da036b7442ef4ea410c679d4cf21830a65), [GPL version 3](../../../docs/licenses/GPL-3.0.txt) |

The Torino authors request that research using these circuits cite F. Corno,
M. Sonza Reorda and G. Squillero, *RT-level ITC’99 benchmarks and first ATPG
results*, IEEE Design & Test of Computers 17(3), 44–53 (2000).
CCSL describes adapting the VHDL for Larry Doolittle's vhd2vl translator and
manually editing the resulting Verilog. The supplied Verilog includes these
edits. [Requested citation](https://doi.org/10.1109/54.867894) · [Third-party notices](../../../docs/THIRD-PARTY.md)

### Changes made for the experiments

The original June 2026 acquisition read Verilog from the translation repository's
then-current main branch and retained the resulting circuits. A per-run digest of
the downloaded temporary RTL was not recorded. The RTL supplied on 2026-11-11
is pinned by commit and SHA-256. Its correspondence to the archived benchmark
is checked at the output of synthesis. This check does not establish a formal
equivalence between the sequential VHDL, the hand-edited Verilog and the
combinationalized host.

| Work and date | Source, transformation and resulting circuit |
|---|---|
| Host netlists, 2026-06-09 | Yosys flattens and synthesizes the CCSL Verilog, synchronizes asynchronous resets and emits BLIF. ABC cuts state elements into scan ports, structurally hashes the circuit and assigns short names. The supplied LUT converter expands the gates into BENCH. |
| Selected LUT cones, 2026-06-23 | The `lut2/` files preserve the two editable LUT2 networks for b14 and b20. ABC maps the corresponding unlocked host to 2-input LUTs. The flat writer extracts the selected output cone. |
| Certified-emitter, reader and cone controls, 2026-08-26 | P40 emits fused and unfused circuits for both recorded keys. P47 translates those eight files to BLIF. P49 emits a locked cone, fixes its explicitly supplied input bits, names ports in cone-support order and pads unused inputs. It also extracts the matching output cone with ABC. |
| PPA, 2026-08-26, 2026-09-18 and 2026-11-10 | P44 selects b14, b17 and b20, plus the SFLL-HD and XOR variants of each. The SFLL transformation uses 16 bits, radius 8, output index 0 and the recorded cube. The XOR placement uses the host name as its seed. September maps each of the nine BENCH inputs. November adds the output adapter before mapping. The netlist writer uses the recorded pin ordering and planted parameters. |

The corresponding build scripts are [RTL conversion](build.py),
[LUT expansion](../../scripts/lut2gate.py), [flat extraction](../../scripts/gen_netlist_data.py),
[certified emitter source](../../extract/Main.agda), [SFLL splicing](../../scripts/splice_sfll.py),
[XOR splicing](../../scripts/splice_xor.py), [structural replay](structures.py),
[fixed input wiring](fix_wires.py) and [port-preserving mapper](../../analysis/ppa_flow.py).
The retained designs and logs are in [recorded inputs and outputs](../raw/).
The licenses for the upstream circuits apply to the corresponding covered circuit
material throughout these transformations.

### Rebuild the six hosts offline

Run from the artifact root with Python 3, Yosys and yosys-abc installed. Select
the desired tool versions on `PATH` and use a fresh output directory outside
this copy. The command verifies all twelve upstream source digests before
synthesis. All six circuit inputs are local.

```sh
python3 -B experiments/data/itc99-source/build.py ../itc-hosts --require-match
```

`--require-match` compares the three archived unlocked P44 hosts. It requires
fresh output and exits with a failure on a difference. b15, b21 and b22 have
no unlocked P44 reference and their JSON records identify this with a null
comparison. For routine setup, `bash experiments/scripts/setup.sh itc99` puts
the circuits in the location used by existing scripts and reuses existing
host files.

The June toolchain used for replay on Intel macOS was Yosys 0.66, commit
`7f8fdfd8d7bc08c749a2a969388d3425d4f369d5`, with the bundled ABC 1.01
compiled 2026-06-01. All six recreated BENCH bodies matched the six retained
June hosts after stripping the dated ABC header. The three public P44 bodies
matched as well. With Yosys 0.68+post at
`c12172fbae8af5e20f6fb52e3d4e92d56ed587b6` and its August ABC, b14 and b20
matched while b17 differed. The report includes both body digests and identifies
whether a cache was used. [Historical Yosys formula](https://github.com/Homebrew/homebrew-core/blob/db26f806fec7d6ac10f275d1ea73d6a5df8e2e0f/Formula/y/yosys.rb)

### Rebuild derived circuit records

Build the Agda extract front-end from this artifact. For physical mapping,
supply the external Nangate45 Liberty file with SHA-256
`2efd0b32eb580e4e60e72fc0575bb3bc69aac907c91d908442e4ae6d7fe55895`.
Use the August ABC build listed in the tool-version record for this stage.
The command below uses the fresh June-toolchain host builds and compares their
BENCH bodies with the corresponding P44 inputs. Omitting `--hosts-dir` starts
at the archived P44 inputs and lets the reader check the downstream stages
independently of the host synthesis version.
[Build instructions](../../../REPRODUCE.md) · [Tool versions](../../configs/tool-versions.txt)

```sh
python3 -B experiments/data/itc99-source/structures.py ../itc-structures \
  --hosts-dir ../itc-hosts --emitter experiments/extract/_bin/Main --lib "$NANGATE45_LIB"
```

Without `--lib`, the command rebuilds the circuit splices, LUT2 and flat cones,
emitter outputs, reader BLIF and fixed-input controls. With the pinned library,
it also reconstructs the September and November mapped Verilog files. Each
comparison identifies the reference file, comparison mode and SHA-256 of the
compared bytes. The structural check compares all declarations and gates.
For ABC-generated files it omits the generated header carrying a path or time.
For BLIF it also omits the file-derived model-name line. For historical
`mapped.v` it canonicalizes the path-derived module identifier. The frozen
files keep their original text. P44 SFLL serialization omits the additional
ordered-input comment printed by the current splicer. [Current PPA experiment](../../analysis/power_revision.py)
