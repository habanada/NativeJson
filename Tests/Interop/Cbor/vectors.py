import json, os, sys
import cbor2
from harness import Tool, norm, parse_ours

VEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cose-examples')


def main():
    files = sorted(os.listdir(VEC))
    tool = Tool('int wrap')
    plain = Tool('')
    total = same_value = same_bytes = 0
    diff = []
    for f in files:
        j = json.load(open(os.path.join(VEC, f), encoding='utf-8'))
        raw = bytes.fromhex(j['output']['cbor'])
        total += 1
        reply = tool.call('D', raw.hex())
        if not reply.startswith('OK '):
            diff.append((f, 'decode', reply)); continue
        try:
            want = norm(cbor2.loads(raw))
        except Exception as e:
            diff.append((f, 'cbor2', str(e))); continue
        got = parse_ours(reply[3:])
        if got == want: same_value += 1
        else: diff.append((f, 'value', reply[3:200]))
        back = tool.call('E', json.dumps(json.loads(reply[3:]), ensure_ascii=True))
        if back == 'OK ' + raw.hex(): same_bytes += 1
        else: diff.append((f, 'bytes', back[:120] + ' vs ' + raw.hex()[:120]))
        p = plain.call('D', raw.hex())
        if not p.startswith('OK '): diff.append((f, 'plain-decode', p))
    print('vectors:', total, 'value equal to cbor2:', same_value, 'byte-identical round trip:', same_bytes)
    for d in diff[:15]: print('  ', d)
    return 0 if not diff else 1


if __name__ == '__main__':
    sys.exit(main())
