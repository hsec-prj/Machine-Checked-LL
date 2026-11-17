"""Explicit, invertible port adapter for ABC's scalar Verilog writer.

ABC loses an output role when a BENCH wire is both INPUT and OUTPUT. Give
every output its own fresh external name before mapping, retaining every
original wire and adding only a BUF. Key/primary input names stay unchanged.
The original source, mapping records and new mapped bytes remain distinct.
"""
import re


def bench_ports(text):
    result = {'inputs': [], 'outputs': []}
    for raw in text.splitlines():
        line = raw.split('#', 1)[0].strip()
        match = re.fullmatch(r'(INPUT|OUTPUT)\s*\(\s*([^\s(),=]+)\s*\)', line, re.I)
        if match:
            result['inputs' if match[1].upper() == 'INPUT' else 'outputs'].append(match[2])
        elif re.match(r'(INPUT|OUTPUT)\b', line, re.I):
            raise ValueError('malformed BENCH port declaration')
    _unique(result)
    return result


def _scalar_port(token):
    token = token.strip()
    if re.fullmatch(r'[A-Za-z_$][A-Za-z0-9_$]*', token):
        return token
    if re.fullmatch(r'\\[^\s,;]+', token):
        return token[1:]
    raise ValueError(f'unsupported mapped scalar port: {token!r}')


def verilog_ports(text):
    """Strict ABC non-ANSI scalar interface, including module header order."""
    text = re.sub(r'//[^\n]*', '', text)
    modules = list(re.finditer(r'\bmodule\s+(?:\\[^\s]+\s+|[A-Za-z_$][A-Za-z0-9_$]*\s*)\((.*?)\)\s*;', text, re.S))
    if len(modules) != 1 or len(re.findall(r'\bendmodule\b', text)) != 1:
        raise ValueError('expected exactly one non-ANSI mapped module')
    header = [_scalar_port(token) for token in modules[0][1].split(',')]
    result = {'inputs': [], 'outputs': []}
    declarations = list(re.finditer(r'\b(input|output|inout)\s+([^;]+);', text, re.S))
    for match in declarations:
        if match[1] == 'inout':
            raise ValueError('unexpected inout in combinational mapping')
        destination = result['inputs' if match[1] == 'input' else 'outputs']
        destination.extend(_scalar_port(token) for token in match[2].split(','))
    _unique(result)
    if header != result['inputs'] + result['outputs']:
        raise ValueError('mapped module header differs from complete ordered input/output declarations')
    return result


def _unique(interface):
    for role, names in interface.items():
        if not names or len(names) != len(set(names)):
            raise ValueError(f'empty or duplicate {role}')


def require_ports(expected, observed):
    """Check every role, name and ordered position; no count-only shortcut."""
    if expected != observed:
        detail = {role: dict(expected=len(expected[role]), observed=len(observed[role]),
                              missing=sorted(set(expected[role])-set(observed[role])),
                              extra=sorted(set(observed[role])-set(expected[role])),
                              order_equal=expected[role] == observed[role])
                  for role in ('inputs', 'outputs')}
        raise ValueError('full port interface mismatch: '+repr(detail))


def output_adapter(net):
    # Use the same Bench type as the caller without adding another import
    # route or changing the delivered historical bench_io module.
    used = set(net.inputs) | set(net.outputs) | {w for w, _, _ in net.gates}
    prefix = 'ppa_output_'
    while any(w.startswith(prefix) for w in used):
        prefix += '_'
    names = [prefix+f'{i:04}' for i in range(len(net.outputs))]
    adapted = type(net)(list(net.inputs), names,
                        list(net.gates)+[(name,'BUF',[old]) for old,name in zip(net.outputs,names)])
    record = dict(input_map=[dict(index=i, original=w, adapted=w) for i,w in enumerate(net.inputs)],
                  output_map=[dict(index=i, original=old, adapted=new,
                                   passthrough=old in net.inputs)
                              for i,(old,new) in enumerate(zip(net.outputs,names))],
                  original_interface=dict(inputs=list(net.inputs),outputs=list(net.outputs)),
                  adapted_interface=dict(inputs=list(adapted.inputs),outputs=list(adapted.outputs)),
                  operation='retain original gates/wires; append one BUF and unique external name per output')
    verify_adapter(net, adapted, record)
    return adapted, record


def verify_adapter(original, adapted, record):
    if record['input_map'] != [dict(index=i, original=w, adapted=w) for i,w in enumerate(original.inputs)]:
        raise ValueError('adapter input identity map mismatch')
    if adapted.inputs != original.inputs or adapted.gates[:len(original.gates)] != original.gates:
        raise ValueError('adapter changed original inputs or logic')
    expected = [(entry['adapted'],'BUF',[entry['original']]) for entry in record['output_map']]
    if adapted.gates[len(original.gates):] != expected:
        raise ValueError('adapter is not exactly a per-output identity buffer')
    if adapted.outputs != [entry['adapted'] for entry in record['output_map']]:
        raise ValueError('adapter output map mismatch')
    if [entry['original'] for entry in record['output_map']] != original.outputs:
        raise ValueError('adapter does not cover all original outputs in order')
    if len(set(adapted.outputs)) != len(original.outputs) or set(adapted.inputs)&set(adapted.outputs):
        raise ValueError('adapter output names are not fresh and disjoint')


def adapter_miter(original, adapted, record):
    """All-output XOR miter under the explicit bijection, without CEC name flags."""
    require_ports(record['original_interface'],dict(inputs=original.inputs,outputs=original.outputs))
    require_ports(record['adapted_interface'],dict(inputs=adapted.inputs,outputs=adapted.outputs))
    if original.inputs != adapted.inputs:
        raise ValueError('miter requires the declared identity input map')
    used=set(original.inputs)|set(original.outputs)|set(adapted.outputs)
    used.update(w for net in (original,adapted) for w,_,_ in net.gates)
    prefix='ppa_miter_'
    while any(w.startswith(prefix) for w in used):
        prefix += '_'
    primary=set(original.inputs)
    def renamed(net,side):
        ren=lambda w:w if w in primary else prefix+side+w
        return [(ren(w),op,[ren(a) for a in args]) for w,op,args in net.gates],ren
    left,lren=renamed(original,'left_');right,rren=renamed(adapted,'right_')
    outputs=[prefix+f'out_{i:04}' for i in range(len(original.outputs))]
    gates=left+right+[(out,'XOR',[lren(entry['original']),rren(entry['adapted'])])
                      for out,entry in zip(outputs,record['output_map'])]
    inverse,zero=prefix+'not',prefix+'zero'
    golden=[(inverse,'NOT',[original.inputs[0]]),(zero,'AND',[original.inputs[0],inverse])]
    golden += [(out,'BUF',[zero]) for out in outputs]
    return type(original)(original.inputs,outputs,gates),type(original)(original.inputs,outputs,golden)
