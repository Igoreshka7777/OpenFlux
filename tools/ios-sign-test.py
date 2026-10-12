"""One diagnostic signing run. No purchases; private outputs stay encrypted."""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import secrets
import stat
import subprocess
import tempfile
import zipfile

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def run(args):
    result = subprocess.run(args, capture_output=True, timeout=120)
    if result.returncode:
        # Tool output can include signing identity and other personal data.
        raise RuntimeError('Signing command failed: ' + Path(args[0]).name)
    return result.stdout


def extract(raw, dest):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        for item in archive.infolist():
            path = (dest / item.filename).resolve()
            if not path.is_relative_to(dest.resolve()) or stat.S_ISLNK(item.external_attr >> 16):
                raise RuntimeError('Unsafe archive entry')
        archive.extractall(dest)


def main():
    os.umask(0o077)
    out = Path('signing-result'); out.mkdir(exist_ok=True)
    report = {'test_only': True, 'real_purchase': False, 'installation_tested': False,
              'signature_verified': False, 'profile_compatible': False, 'issues': []}
    keychain = None
    try:
        data = json.loads(os.environ.pop('SIGN_TEST_INPUT'))
        ipa = next(Path('unsigned').rglob('OpenFlux-iOS-454-unsigned.ipa'))
        raw = ipa.read_bytes()
        if hashlib.sha256(raw).hexdigest() != 'ead431742aee1b7a686c11bf3e3a90982bcda5f15a284c7d88dcc17ac8ba0410':
            raise RuntimeError('Unsigned IPA checksum mismatch')
        with tempfile.TemporaryDirectory(dir=os.environ['RUNNER_TEMP']) as folder:
            work = Path(folder); certificates = work/'certificates'; certificates.mkdir()
            extract(base64.b64decode(data['certificate_zip']), certificates)
            p12 = next(certificates.rglob('*.p12'))
            profiles = list(certificates.rglob('*.mobileprovision'))
            if len(profiles) != 1:
                raise RuntimeError('This diagnostic expects the selected single-profile certificate')
            profile_path = profiles[0]
            profile = plistlib.loads(run(['security','cms','-D','-i',str(profile_path)]))
            ent_profile = profile['Entitlements']
            prefix = profile['ApplicationIdentifierPrefix'][0] + '.'
            team = profile['TeamIdentifier'][0]
            if data['udid'].upper() not in [d.upper() for d in profile.get('ProvisionedDevices',[])]:
                raise RuntimeError('Certificate profile does not include the selected iPhone')
            private, certificate, chain = pkcs12.load_key_and_certificates(p12.read_bytes(),data['password'].encode())
            if not private or not certificate:
                raise RuntimeError('Certificate identity missing')
            cert_der = certificate.public_bytes(serialization.Encoding.DER)
            if cert_der not in profile.get('DeveloperCertificates',[]):
                raise RuntimeError('Certificate does not match profile')
            identity = hashlib.sha1(cert_der).hexdigest().upper()
            keychain = work/'test.keychain-db'; keypass = secrets.token_urlsafe(24)
            run(['security','create-keychain','-p',keypass,str(keychain)])
            run(['security','set-keychain-settings','-lut','1200',str(keychain)])
            run(['security','unlock-keychain','-p',keypass,str(keychain)])
            run(['security','import',str(p12),'-k',str(keychain),'-P',data['password'],'-T','/usr/bin/codesign'])
            run(['security','set-key-partition-list','-S','apple-tool:,apple:','-s','-k',keypass,str(keychain)])
            package=work/'package';package.mkdir()
            run(['ditto','-x','-k',str(ipa.resolve()),str(package)])
            app=package/'Payload/OpenFlux.app'
            bundles=[*sorted((app/'PlugIns').glob('*.appex')),app]
            if not (app/'PlugIns/PacketTunnel.appex').is_dir():
                raise RuntimeError('VPN extension missing')
            source=Path('openflux-ios/VKTurnProxy')
            sources={
                'OpenFlux.app':source/'VKTurnProxy/VKTurnProxy.entitlements',
                'PacketTunnel.appex':source/'PacketTunnel/PacketTunnel.entitlements',
            }
            # Sign framework code before sealing the containing bundles.
            nested=[*app.rglob('*.framework'),*app.rglob('*.dylib')]
            for binary in sorted(nested,key=lambda p:len(p.parts),reverse=True):
                run(['codesign','--force','--sign',identity,'--keychain',str(keychain),'--timestamp=none',str(binary)])
            for bundle in bundles:
                info=plistlib.loads((bundle/'Info.plist').read_bytes());bid=info['CFBundleIdentifier']
                entitlement=plistlib.loads(sources[bundle.name].read_bytes()) if bundle.name in sources else {}
                def expand(v):
                    if isinstance(v,str):return v.replace('$(AppIdentifierPrefix)',prefix)
                    if isinstance(v,list):return [expand(x) for x in v]
                    if isinstance(v,dict):return {k:expand(x) for k,x in v.items()}
                    return v
                entitlement=expand(entitlement)
                entitlement.update({'application-identifier':prefix+bid,'com.apple.developer.team-identifier':team,'get-task-allow':False})
                def allows(actual, granted):
                    if isinstance(actual,list):return isinstance(granted,list) and all(any(allows(x,y) for y in granted) for x in actual)
                    if isinstance(actual,str) and isinstance(granted,str):return actual==granted or (granted.endswith('*') and actual.startswith(granted[:-1]))
                    return actual==granted
                for name,value in entitlement.items():
                    if not allows(value,ent_profile.get(name)):
                        report['issues'].append({'bundle':bid,'entitlement':name,'reason':'not permitted by supplied profile'})
                ent_file=work/(bundle.name+'.plist');ent_file.write_bytes(plistlib.dumps(entitlement))
                (bundle/'embedded.mobileprovision').write_bytes(profile_path.read_bytes())
                run(['codesign','--force','--sign',identity,'--keychain',str(keychain),'--timestamp=none','--generate-entitlement-der','--entitlements',str(ent_file),str(bundle)])
                run(['codesign','--verify','--strict',str(bundle)])
            run(['codesign','--verify','--deep','--strict',str(app)])
            report['signature_verified']=True
            report['profile_compatible']=not report['issues']
            signed=work/'OpenFlux-iOS-454-signing-test.ipa'
            run(['ditto','-c','-k','--keepParent',str(package/'Payload'),str(signed)])
            signed_bytes=signed.read_bytes();report['ipa_sha256']=hashlib.sha256(signed_bytes).hexdigest()
            nonce=os.urandom(12)
            encrypted=AESGCM(base64.b64decode(data['artifact_key'])).encrypt(nonce,signed_bytes,b'OpenFlux signing test')
            (out/'OpenFlux-iOS-454-signing-test.ipa.enc').write_bytes(nonce+encrypted)
            report['ready_for_customer_delivery']=False
    except Exception as exc:
        report['error']=str(exc) if isinstance(exc,RuntimeError) else type(exc).__name__
        raise
    finally:
        if keychain:
            subprocess.run(['security','delete-keychain',str(keychain)],capture_output=True)
        (out/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print(json.dumps(report,ensure_ascii=False))


if __name__=='__main__':main()
