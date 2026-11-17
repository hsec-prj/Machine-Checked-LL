"""Shared UTF-8 table IO; schemas and captions remain in each generator."""
import csv
from pathlib import Path

def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as stream:
        return list(csv.DictReader((line for line in stream if not line.startswith("#")), delimiter="\t"))

def write_tex(path, text):
    Path(path).write_text(text, encoding="utf-8")

def write_tsv(path, rows, fields=None):
    if fields is None:
        fields = list(rows[0])
    with Path(path).open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
