"""Build/run a game-only Android native multi-pointer Instrumentation driver.

No general device UI automation is exposed. The companion APK targets only
org.spinningmetal.prototype and verifies window focus before every MotionEvent.
Native points map through an explicit safe640x360 letterboxed viewport.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shlex
import re
import subprocess
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
sys.path.insert(0,str(ROOT/'tools/workspace'))
import windows_checkpoint as pipeline
import workspace
PACKAGE='org.spinningmetal.qa003a'
TARGET='org.spinningmetal.prototype'
DRIVER=PACKAGE+'/org.spinningmetal.qa003a.TouchDriver'
MANIFEST='''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.spinningmetal.qa003a">
  <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="36" />
  <application android:label="Spinning Metal003A touch QA" android:testOnly="true" android:hasCode="true" />
  <instrumentation android:name="org.spinningmetal.qa003a.TouchDriver" android:targetPackage="org.spinningmetal.prototype" android:functionalTest="true" android:handleProfiling="false" />
</manifest>
'''

def execute(command: list[str],log: Path,timeout=180) -> dict:
    return pipeline.run_logged(command,log,timeout)

def adb_command(adb: Path,serial: str,args: list[str]) -> list[str]:
    if not serial or any(c.isspace() for c in serial): raise ValueError('An explicit single device serial is required')
    return [str(adb),'-s',serial,*args]

def build(args) -> dict:
    task=workspace.create_task_workspace('003A')
    name='003a_android_instrumentation_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    stage=task/'temp'/name;stage.mkdir()
    tools=args.sdk/'build-tools'/args.build_tools
    android=args.sdk/'platforms'/'android-36'/'android.jar'
    java=args.jdk/'bin/java.exe';javac=args.jdk/'bin/javac.exe'
    for path in [android,java,javac,args.keystore,tools/'aapt2.exe',tools/'zipalign.exe',tools/'lib/d8.jar',tools/'lib/apksigner.jar']:
        assert path.is_file(),f'Missing Android tool: {path}'
    classes=stage/'classes';classes.mkdir()
    dex=stage/'dex';dex.mkdir()
    manifest=stage/'AndroidManifest.xml';manifest.write_text(MANIFEST,encoding='utf-8')
    logs=[]
    logs.append(execute([str(javac),'-source','8','-target','8','-classpath',str(android),'-d',str(classes),str(Path(__file__).with_name('TouchDriver.java'))],task/'logs'/(name+'_javac.log')))
    logs.append(execute([str(java),'-cp',str(tools/'lib/d8.jar'),'com.android.tools.r8.D8','--min-api','23','--lib',str(android),'--output',str(dex),*[str(p) for p in sorted(classes.rglob('*.class'))]],task/'logs'/(name+'_dex.log')))
    unsigned=stage/'unsigned.apk';aligned=stage/'aligned.apk'
    logs.append(execute([str(tools/'aapt2.exe'),'link','-I',str(android),'--manifest',str(manifest),'-o',str(unsigned)],task/'logs'/(name+'_aapt.log')))
    with zipfile.ZipFile(unsigned,'a',zipfile.ZIP_DEFLATED) as file: file.write(dex/'classes.dex','classes.dex')
    logs.append(execute([str(tools/'zipalign.exe'),'-f','4',str(unsigned),str(aligned)],task/'logs'/(name+'_align.log')))
    output=args.output or stage/'SpinningMetal-003A-touch-instrumentation.apk'
    assert not output.exists(),'Preserve a previous built tool'
    output.parent.mkdir(parents=True,exist_ok=True)
    # This deliberately uses the same public Android debug identity as the
    # exported test game. No release key or credentials are ever read/exported.
    signer=[str(java),'-jar',str(tools/'lib/apksigner.jar'),'sign','--ks',str(args.keystore),
            '--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',str(output),str(aligned)]
    signing=execute(signer,task/'logs'/(name+'_sign.log'))
    signing['command']=['Android debug APK signing (arguments omitted)']
    logs.append(signing)
    logs.append(execute([str(java),'-jar',str(tools/'lib/apksigner.jar'),'verify',str(output)],task/'logs'/(name+'_verify.log')))
    record={'scope':'Native test-only Instrumentation APK targeting only Spinning Metal; real bounded multi-pointer MotionEvent injection',
            'package':PACKAGE,'target':TARGET,'driver':DRIVER,'apk':str(output),'sha256':pipeline.sha256(output),
            'source_sha256':{str(p.relative_to(ROOT)):pipeline.sha256(p) for p in [Path(__file__).resolve(),Path(__file__).with_name('TouchDriver.java')]},'logs':logs}
    report=task/'manifests'/(name+'.json');report.write_text(json.dumps(record,indent=2)+'\n')
    record['manifest']=str(report)
    return record

def run(args) -> dict:
    script=None
    if args.session:
        assert re.fullmatch('[0-9a-f]{32}',args.session),'A bounded hexadecimal session is required'
    else:
        assert args.script is not None,'--script or --session is required'
        script=json.loads(args.script.read_text(encoding='utf-8-sig'))
        assert set(script)<= {'viewport','steps'} and len(script['viewport'])==4
        assert 1<=len(script['steps'])<=240
        assert all(step['type'] in ['down','move','up','cancel','wait'] for step in script['steps'])
    if args.install:
        assert args.install.is_file()
        execute(adb_command(args.adb,args.serial,['install','-r','-t',str(args.install)]),args.log.with_name(args.log.stem+'_install.log'))
    shell=['am','instrument','-w','-r','-e','session',args.session,DRIVER] if args.session else ['am','instrument','-w','-r','-e','script',json.dumps(script,separators=(',',':'),ensure_ascii=True),DRIVER]
    result=execute(adb_command(args.adb,args.serial,['shell',' '.join(shlex.quote(s) for s in shell)]),args.log,960 if args.session else 180)
    output=args.log.read_text(encoding='utf-8',errors='replace')
    assert 'INSTRUMENTATION_RESULT: passed=true' in output and 'INSTRUMENTATION_CODE: -1' in output,output
    return {'passed':True,'serial':args.serial,'driver':DRIVER,'session':args.session,'script':str(args.script) if args.script else None,'script_sha256':pipeline.sha256(args.script) if args.script else None,'process':result}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='mode',required=True)
    make=sub.add_parser('build')
    make.add_argument('--sdk',type=Path,default=Path(os.environ.get('LOCALAPPDATA',''))/'Android/Sdk')
    make.add_argument('--jdk',type=Path,default=Path(r'C:\Program Files\Microsoft\jdk-25.0.4.101-hotspot'))
    make.add_argument('--build-tools',default='36.1.0')
    make.add_argument('--keystore',type=Path,required=True)
    make.add_argument('--output',type=Path)
    inject=sub.add_parser('run')
    inject.add_argument('--adb',type=Path,default=Path(r'C:\adb\adb.exe'))
    inject.add_argument('--serial',required=True)
    source=inject.add_mutually_exclusive_group(required=True)
    source.add_argument('--script',type=Path)
    source.add_argument('--session')
    inject.add_argument('--log',type=Path,required=True)
    inject.add_argument('--install',type=Path)
    args=parser.parse_args()
    print(json.dumps(build(args) if args.mode=='build' else run(args),indent=2))

if __name__=='__main__': main()
