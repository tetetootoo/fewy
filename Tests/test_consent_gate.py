"""Run read-only TCF gate regression fixtures with the project's installed Swift compiler.
No UMP/device preferences are modified. Run: python3 Tests/test_consent_gate.py
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def number(value, width):
    return f'{value:0{width}b}'


def encode(bits):
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    bits += '0' * (-len(bits) % 6)
    return ''.join(alphabet[int(bits[i:i + 6], 2)] for i in range(0, len(bits), 6))


def fixture(name, purposes=(1, 3, 4), interests=(2, 7, 9, 10), vc=True, vi=True,
            restrictions=(), ranged=False, policy=4, disclosed=True, npa=True, personalized=True):
    pc = ''.join('1' if i in purposes else '0' for i in range(1, 25))
    li = ''.join('1' if i in interests else '0' for i in range(1, 25))

    def vendor(flag):
        if ranged:
            return number(755, 16) + '1' + number(int(flag), 12) + ('0' + number(755, 16) if flag else '')
        return number(755, 16) + '0' + '0' * 754 + str(int(flag))

    core = number(2, 6) + '0' * 126 + number(policy, 6) + '0' * 14 + pc + li + '0' * 13
    core += vendor(vc) + vendor(vi) + number(len(restrictions), 12)
    for purpose, kind in restrictions:
        core += number(purpose, 6) + number(kind, 2) + number(1, 12) + '0' + number(755, 16)
    tc = encode(core)
    if policy >= 5 and disclosed:
        tc += '.' + encode('001' + vendor(True))
    return dict(name=name, values={
        'IABTCF_TCString': tc,
        'IABTCF_PurposeConsents': pc,
        'IABTCF_PurposeLegitimateInterests': li,
        'IABTCF_VendorConsents': '0' * 754 + str(int(vc)),
        'IABTCF_VendorLegitimateInterests': '0' * 754 + str(int(vi)),
    }, npa=npa, personalized=personalized)


cases = [
    fixture('consent'),
    fixture('NPA without personalization', purposes=(1,), personalized=False),
    fixture('rejection', purposes=(), vc=False, npa=False, personalized=False),
    fixture('Google declined', vc=False, npa=False, personalized=False),
    fixture('Google LI objection', vi=False, npa=False, personalized=False),
    fixture('purpose LI objection', interests=(2, 7, 9), npa=False, personalized=False),
    fixture('publisher prohibition', restrictions=((7, 0),), npa=False, personalized=False),
    fixture('publisher requires consent, absent', restrictions=((7, 1),), npa=False, personalized=False),
    fixture('publisher requires consent, granted', purposes=(1, 3, 4, 7), restrictions=((7, 1),)),
    fixture('consent does not substitute for default LI', purposes=(1, 2, 3, 4, 7, 9, 10), interests=(), npa=False, personalized=False),
    fixture('consent bases for all flexible purposes', purposes=(1, 2, 3, 4, 7, 9, 10), interests=(), restrictions=tuple((i, 1) for i in (2, 7, 9, 10))),
    fixture('LI restriction cannot replace P1 consent', restrictions=((1, 2),), npa=False, personalized=False),
    fixture('range encoded vendors', ranged=True),
    fixture('TCF 2.3 disclosed', policy=5),
    fixture('TCF 2.3 not disclosed', policy=5, disclosed=False, npa=False, personalized=False),
]
case = fixture('UMP uses 11 purpose bits')
for key in ['IABTCF_PurposeConsents', 'IABTCF_PurposeLegitimateInterests']:
    case['values'][key] = case['values'][key][:11]
cases.append(case)
for key, value in [('IABTCF_TCString', ''), ('IABTCF_TCString', 'invalid'),
                   ('IABTCF_PurposeConsents', ''), ('IABTCF_VendorConsents', '0' * 755),
                   ('IABTCF_PurposeLegitimateInterests', '')]:
    case = fixture('missing/malformed/inconsistent ' + key, npa=False, personalized=False)
    case['values'][key] = value
    cases.append(case)

source = Path('App/FewyAds.swift').read_text()
source = 'import Foundation\n' + source[source.index('private struct GoogleTCFConsent'):]
harness = r'''
let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
for fixture in fixtures {
    let suite = "FewyGateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    for (key, value) in fixture["values"] as! [String: String] { defaults.set(value, forKey: key) }
    let gate = GoogleTCFConsent(defaults: defaults)
    let name = fixture["name"] as! String
    precondition((gate?.allowsNonPersonalized ?? false) == fixture["npa"] as! Bool, "NPA: \(name)")
    precondition((gate?.allowsPersonalized ?? false) == fixture["personalized"] as! Bool, "Personalized: \(name)")
    print("PASS \(name)")
}
'''
with tempfile.TemporaryDirectory(prefix='fewy-gate-') as folder:
    path = Path(folder)
    (path / 'main.swift').write_text(source + harness)
    (path / 'fixtures.json').write_text(json.dumps(cases))
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['xcrun', 'swift', '-module-cache-path', str(path / 'cache'), str(path / 'main.swift'), str(path / 'fixtures.json')], env=env, check=True)
