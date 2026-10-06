"""Operate only Spinning Metal's explicit isolated Android acceptance session."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
import uuid

ROOT=Path(__file__).resolve().parents[2]
QA=ROOT.parent/'GyroBrothers-QA'/'003A'
ADB=Path.home()/'AppData/Local/Android/Sdk/platform-tools/adb.exe'
PACKAGE='org.spinningmetal.prototype'

def adb(serial,*args,input=None,check=True,binary=False):
    result=subprocess.run([str(ADB),'-s',serial,*args],input=input,capture_output=True,text=not binary,timeout=120)
    if check and result.returncode: raise RuntimeError(result.stderr if result.stderr else result.stdout)
    return result.stdout

def read_json(serial,path):
    return json.loads(adb(serial,'shell','run-as',PACKAGE,'cat',path))

def write_device(serial,path,data):
    # JSON never becomes shell syntax. Only a bounded, app-owned relative path is used.
    if not path.startswith('files/qa003a/') or '..' in path: raise ValueError('Outside our explicit QA session')
    remote='/data/local/tmp/spinningmetal_003a_'+uuid.uuid4().hex+'.json'
    local=QA/'temp'/Path(remote).name
    local.write_text(json.dumps(data),encoding='utf-8')
    adb(serial,'push',str(local),remote)
    adb(serial,'shell','run-as',PACKAGE,'cp',remote,path+'.tmp')
    adb(serial,'shell','run-as',PACKAGE,'mv',path+'.tmp',path)

def initialise(serial):
    run_id=uuid.uuid4().hex
    adb(serial,'shell','run-as',PACKAGE,'mkdir','-p','files/qa003a/'+run_id)
    write_device(serial,'files/qa003a/request.json',{'run_id':run_id})
    record={'serial':serial,'run_id':run_id,'sequence':0,'created':time.time()}
    target=QA/'manifests'/('003a_android_session_'+run_id+'.json')
    target.write_text(json.dumps(record,indent=2)+'\n')
    return target

def command(session,steps,finish=False):
    record=json.loads(session.read_text()); serial=record['serial']; run_id=record['run_id']
    state=read_json(serial,'files/qa003a/'+run_id+'/state.json')
    record['sequence']+=1; sequence=record['sequence']
    data={'sequence':sequence,'viewport':state['native_surface'],'steps':steps}
    if finish: data={'sequence':sequence,'finish':True}
    base='files/qa003a/'+run_id+'/'
    write_device(serial,base+'touch_command.json',data)
    log=QA/'manifests'/('003a_android_command_'+run_id+'_'+str(sequence)+'.json')
    for _ in range(600):
        try:
            receipt=read_json(serial,base+'touch_receipt_'+str(sequence)+'.json')
            break
        except (RuntimeError,json.JSONDecodeError): time.sleep(.1)
    else: raise TimeoutError('Native Android touch driver did not acknowledge the command')
    record['last_receipt']=receipt; session.write_text(json.dumps(record,indent=2)+'\n')
    log.write_text(json.dumps({'command':data,'receipt':receipt},indent=2)+'\n')
    if not receipt.get('passed'): raise RuntimeError(receipt)
    return receipt

def capture(session,label):
    record=json.loads(session.read_text());serial=record['serial'];run_id=record['run_id']
    state=read_json(serial,'files/qa003a/'+run_id+'/state.json')
    target=QA/'manifests'/('003a_android_'+run_id+'_'+label+'.json')
    target.write_text(json.dumps(state,indent=2)+'\n')
    image=QA/'images'/('003a_android_'+run_id+'_'+label+'.png')
    image.write_bytes(adb(serial,'exec-out','screencap','-p',binary=True))
    return {'state':str(target),'image':str(image),'screen':state['screen'],'battle_status':state['battle_status'],'elapsed':state['elapsed'],'viewport':state['native_surface'],'fps':state['fps']}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['init','state','capture','tap','drag','command','finish'])
    p.add_argument('--serial');p.add_argument('--session',type=Path);p.add_argument('--x',type=float);p.add_argument('--y',type=float);p.add_argument('--to-x',type=float);p.add_argument('--to-y',type=float);p.add_argument('--ms',type=int,default=700);p.add_argument('--label',default='capture');p.add_argument('--script',type=Path)
    args=p.parse_args()
    if args.mode=='init': result={'session':str(initialise(args.serial))}
    elif args.mode=='state':
        d=json.loads(args.session.read_text());result=read_json(d['serial'],'files/qa003a/'+d['run_id']+'/state.json')
    elif args.mode=='capture': result=capture(args.session,args.label)
    elif args.mode=='finish': result=command(args.session,[],True)
    elif args.mode=='command': result=command(args.session,json.loads(args.script.read_text())['steps'])
    else:
        steps=[{'type':'down','id':0,'point':[args.x,args.y],'ms':60}]
        if args.mode=='drag':steps.append({'type':'move','pointers':[{'id':0,'point':[args.to_x,args.to_y]}],'ms':args.ms,'samples':30})
        steps += [{'type':'up','id':0},{'type':'wait','ms':250}]
        result=command(args.session,steps)
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
