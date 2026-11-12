import re, base64, json, math, random, struct, subprocess, sys, os
from decimal import Decimal
import cbor2

HERE = os.path.dirname(os.path.abspath(__file__))
EXE = os.environ.get('CBOR_INTEROP_EXE', os.path.join(HERE, 'CborInterop.exe'))


class Tool:
    def __init__(self, flags):
        self.p = subprocess.Popen([EXE], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.p.stdin.write((flags + '\n').encode())

    def call(self, kind, payload):
        self.p.stdin.write(('%s %s\n' % (kind, payload)).encode('utf-8'))
        self.p.stdin.flush()
        line = self.p.stdout.readline().decode('utf-8').rstrip('\r\n')
        return line

    def close(self):
        self.p.stdin.close()
        self.p.wait()


def b64u(b):
    return base64.urlsafe_b64encode(b).decode().rstrip('=')


def norm(v):
    if isinstance(v, bool) or v is None or isinstance(v, str):
        return v
    if isinstance(v, int):
        return Decimal(v)
    if isinstance(v, float):
        return Decimal(repr(v))
    if isinstance(v, Decimal):
        return v
    if isinstance(v, bytes):
        return {'@bytes': b64u(v)}
    if isinstance(v, (list, tuple)):
        return [norm(x) for x in v]
    if isinstance(v, (dict, cbor2.frozendict)):
        return {(str(k) if isinstance(k, int) else k): norm(x) for k, x in v.items()}
    if isinstance(v, cbor2.CBORTag):
        return {'@tag': Decimal(v.tag), '@value': norm(v.value)}
    raise TypeError(type(v))


def parse_ours(text):
    return json.loads(text, parse_float=Decimal, parse_int=Decimal)


def rnd_float(r):
    v = rnd_float_raw(r)
    return v if math.isfinite(v) else 0.5


def rnd_float_raw(r):
    k = r.randrange(8)
    if k == 0: return r.uniform(-1e3, 1e3)
    if k == 1: return float(r.randrange(-2000, 2000)) / 8
    if k == 2: return struct.unpack('>f', struct.pack('>I', r.getrandbits(32)))[0] if True else 0.0
    if k == 3: return r.choice([5.960464477539063e-08, 65504.0, 1.0e300, -1.0e-300, 5e-324, 1.7976931348623157e308, 0.1, 0.2, 0.3, 100000.0, 3.4028234663852886e38])
    if k == 4: return struct.unpack('>d', struct.pack('>Q', r.getrandbits(64)))[0]
    if k == 5: return r.random()
    if k == 6: return float(r.randrange(-10**6, 10**6))
    return r.choice([0.0, -0.0, 1.5, -4.1, 1.1])


def rnd_str(r):
    alphabet = ['a', 'b', 'Z', '0', ' ', 'é', 'ß', '水', '😀', '\n', '"', '\\', '/']
    return ''.join(r.choice(alphabet) for _ in range(r.randrange(0, 8)))


def rnd_int(r):
    k = r.randrange(6)
    if k == 0: return r.randrange(-30, 30)
    if k == 1: return r.randrange(-2**31, 2**31)
    if k == 2: return r.randrange(-2**63, 2**64)
    if k == 3: return r.choice([2**64 - 1, -2**64, 2**64, -2**64 - 1, 2**63, -2**63 - 1, 255, 256, 65535, 65536, 23, 24])
    if k == 4: return r.randrange(-2**200, 2**200)
    return r.randrange(0, 1000)


def rnd_value(r, depth, bytes_ok, tags_ok, intkeys):
    k = r.randrange(11 if depth < 4 else 7)
    if k == 0: return None
    if k == 1: return r.random() < 0.5
    if k in (2, 3): return rnd_int(r)
    if k == 4: return rnd_float(r)
    if k == 5: return rnd_str(r)
    if k == 6:
        return bytes(r.getrandbits(8) for _ in range(r.randrange(0, 10))) if bytes_ok else rnd_str(r)
    if k in (7, 8): return [rnd_value(r, depth + 1, bytes_ok, tags_ok, intkeys) for _ in range(r.randrange(0, 5))]
    if k == 9:
        d = {}
        for _ in range(r.randrange(0, 5)):
            if intkeys and r.random() < 0.5: key = rnd_int(r) if r.random() < 0.5 else r.randrange(-24, 30)
            else: key = rnd_str(r)
            d[key] = rnd_value(r, depth + 1, bytes_ok, tags_ok, intkeys)
        return d
    if tags_ok:
        return cbor2.CBORTag(r.choice([5, 6, 7, 16, 18, 24, 32, 55799, 1000, 2**32, 2**40 + 7]), rnd_value(r, depth + 1, bytes_ok, tags_ok, intkeys)) if False else cbor2.CBORTag(r.choice([6, 7, 16, 18, 24, 32, 55799, 1000, 2**32, 2**40 + 7]), rnd_value(r, depth + 1, bytes_ok, tags_ok, intkeys))
    return None


INTLIKE = re.compile(r'^(0|-?[1-9][0-9]*)$')


def has_bigkey(v):
    if isinstance(v, (dict, cbor2.frozendict)):
        return any((not isinstance(k, str) and not (-2**64 <= k < 2**64)) or (isinstance(k, str) and INTLIKE.match(k)) for k in v) or any(has_bigkey(x) for x in v.values())
    if isinstance(v, list): return any(has_bigkey(x) for x in v)
    if isinstance(v, cbor2.CBORTag): return has_bigkey(v.value)
    return False


def has_nonunique_keys(v):
    if isinstance(v, (dict, cbor2.frozendict)):
        ks = [str(k) for k in v]
        if len(set(ks)) != len(ks): return True
        return any(has_nonunique_keys(x) for x in v.values())
    if isinstance(v, list): return any(has_nonunique_keys(x) for x in v)
    if isinstance(v, cbor2.CBORTag): return has_nonunique_keys(v.value)
    return False


def run(n, seed):
    r = random.Random(seed)
    dec = Tool('int wrap')
    fails = {'A': 0, 'B': 0, 'C': 0}
    counts = {'A': 0, 'B': 0, 'C': 0}
    shown = 0

    def report(kind, msg):
        nonlocal shown
        fails[kind] += 1
        if shown < 12:
            shown += 1
            print('FAIL', kind, msg[:400])

    for i in range(n):
        v = rnd_value(r, 0, True, True, True)
        if has_nonunique_keys(v): continue
        for canonical in (False, True):
            data = cbor2.dumps(v, canonical=canonical)
            counts['A'] += 1
            reply = dec.call('D', data.hex())
            if not reply.startswith('OK '):
                report('A', 'decode %s -> %s' % (data.hex(), reply)); continue
            try:
                ours = parse_ours(reply[3:])
            except Exception as e:
                report('A', 'unparsable %s' % reply); continue
            if ours != norm(v):
                report('A', 'mismatch %s\n  ours %r\n  want %r' % (data.hex(), ours, norm(v)))
        data = cbor2.dumps(v, canonical=True)
        if data and not has_bigkey(v):
            counts['C'] += 1
            reply = dec.call('D', data.hex())
            if reply.startswith('OK '):
                back = dec.call('E', json.dumps(json.loads(reply[3:]), ensure_ascii=True))
                if back != 'OK ' + data.hex():
                    report('C', 'roundtrip %s\n  json %s\n  back %s' % (data.hex(), reply[3:], back))

    enc = Tool('int')
    for i in range(n):
        v = rnd_value(r, 0, False, False, True)
        if has_nonunique_keys(v): continue
        text = json.dumps(v, ensure_ascii=True)
        counts['B'] += 1
        reply = enc.call('E', text)
        if not reply.startswith('OK '):
            report('B', 'encode %s -> %s' % (text, reply)); continue
        try:
            back = cbor2.loads(bytes.fromhex(reply[3:]))
        except Exception as e:
            report('B', 'cbor2 rejects %s (%s) for %s' % (reply[3:], e, text)); continue
        if norm(back) != norm(v):
            report('B', 'mismatch %s\n  cbor2 %r\n  want  %r' % (text, back, v))
    dec.close(); enc.close()
    print('A decode vs cbor2:', counts['A'], 'checked,', fails['A'], 'failed')
    print('B encode read by cbor2:', counts['B'], 'checked,', fails['B'], 'failed')
    print('C canonical round trip:', counts['C'], 'checked,', fails['C'], 'failed')
    return sum(fails.values())


if __name__ == '__main__':
    sys.exit(1 if run(int(sys.argv[1]), int(sys.argv[2])) else 0)
