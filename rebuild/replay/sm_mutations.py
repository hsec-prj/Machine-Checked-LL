"""Recreate the 33 fixed regression inputs from the exact corresponding local compiler outputs."""
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
CATALOG_SHA256 = 'abaae7d5428743a2ef86807785946a40ce91127145f0167d511bff158d572d9f'
def hash_bytes(data):
    return hashlib.sha256(data).hexdigest()
TOKEN = re.compile(rb'[A-Za-z0-9_]+')


def mutant_bytes(original: bytes, cls: str) -> bytes:
    data = (HERE/'m-fixtures.json').read_bytes()
    if hash_bytes(data) != CATALOG_SHA256:
        raise ValueError('Fixed regression catalog changed')
    catalog = json.loads(data)
    fixture = catalog.get(hash_bytes(original), {}).get(cls)
    if fixture is None:
        raise ValueError('Unrecognized fixture digest or fault class')
    # All coordinates refer to the unmodified pinned fixture, including line endings.
    lines = original.splitlines(keepends=True)
    for change in fixture['edits']:
        index, op, *fields = change
        line = lines[index]
        if op == 'omit-record':
            lines[index] = b''
        elif op == 'prepend-test-constant':
            # A new, unconnected regression-only declaration in the emitter namespace.
            lines[index] = b'hc0' + b' = ' + b'vdd()\n' + line
        else:
            ordinal, = fields
            token = list(TOKEN.finditer(line))[ordinal]
            value = token.group()
            if op == 'toggle-constant':
                new = {b'vdd':b'gnd',b'gnd':b'vdd'}[value]
            elif op == 'increment-ordinal':
                number = re.fullmatch(rb'([a-zA-Z_]+)([0-9]+)',value)
                if number is None:
                    raise ValueError('Expected a compiler-generated ordinal')
                new = number[1] + str(int(number[2])+1).encode()
            else:
                raise ValueError(f'Unknown fixed edit {op}')
            lines[index] = line[:token.start()] + new + line[token.end():]
    result = b''.join(lines)
    if hash_bytes(result) != fixture['sha256']:
        raise ValueError('Regenerated fixture differs from its historical digest')
    return result
