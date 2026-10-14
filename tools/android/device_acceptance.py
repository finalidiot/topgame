"""Operate only Spinning Metal's explicit isolated Android acceptance session."""
from __future__ import annotations
import argparse
import hashlib
import json
import copy
import math
import re
from pathlib import Path
import subprocess
import time
import uuid

ROOT=Path(__file__).resolve().parents[2]
QA=ROOT.parent/'GyroBrothers-QA'/'003A'
ADB=Path.home()/'AppData/Local/Android/Sdk/platform-tools/adb.exe'
PACKAGE='org.spinningmetal.prototype'
NATIVE_SIZE=[800,480]
CONTENT_SIZE=[640,360]
CONTENT_ORIGIN=[80,60]

def _numbers(value,count,label,positive=False):
    if not isinstance(value,(list,tuple)) or len(value)!=count:
        raise ValueError(label+' requires '+str(count)+' numeric values')
    if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in value):
        raise ValueError(label+' must be finite numeric values')
    if positive and any(v<=0 for v in value):raise ValueError(label+' must be positive')
    return list(value)

def coordinate_geometry(state=None):
    """Actual canvas geometry, with an explicit exact historical-state fallback."""
    if state is None:
        return {'canvas':NATIVE_SIZE.copy(),'battle':CONTENT_SIZE.copy(),'battle_origin':CONTENT_ORIGIN.copy(),
                'battle_scale':1.0,'menu':CONTENT_SIZE.copy(),'menu_origin':CONTENT_ORIGIN.copy(),'menu_scale':1.0}
    if 'canvas_size' not in state:
        if state.get('viewport')!=NATIVE_SIZE or state.get('combat_viewport')!=CONTENT_SIZE or state.get('arena_origin')!=CONTENT_ORIGIN:
            raise ValueError('Legacy state must report exact800x480 canvas and640x360 arena at80,60')
        geometry=coordinate_geometry()
    else:
        canvas=_numbers(state['canvas_size'],2,'canvas_size',True)
        if any(v>8192 for v in canvas):raise ValueError('Canvas size exceeds bounded native instrumentation')
        if state.get('viewport')!=canvas:raise ValueError('Canvas size differs from actual game viewport')
        battle=_numbers(state.get('combat_viewport'),2,'combat_viewport',True)
        if battle!=CONTENT_SIZE:raise ValueError('Canonical combat world must remain640x360')
        arena=_numbers(state.get('arena_rect'),4,'arena_rect')
        if arena[0]<0 or arena[1]<0 or arena[2]<=0 or arena[3]<=0 or arena[0]+arena[2]>canvas[0]+1e-5 or arena[1]+arena[3]>canvas[1]+1e-5:
            raise ValueError('Arena rectangle lies outside the actual canvas')
        scale=_numbers([state.get('arena_scale')],1,'arena_scale',True)[0]
        if any(abs(arena[i+2]-battle[i]*scale)>1e-4 for i in range(2)):
            raise ValueError('Arena scale must preserve uniform canonical world projection')
        if state.get('arena_origin')!=arena[:2]:raise ValueError('Arena origin differs from actual rectangle')
        menu=_numbers(state.get('menu_native_view'),2,'menu_native_view',True)
        if menu!=CONTENT_SIZE:raise ValueError('Authored menu coordinates must remain640x360')
        menu_origin=_numbers(state.get('menu_origin'),2,'menu_origin')
        menu_scale=_numbers([state.get('menu_scale')],1,'menu_scale',True)[0]
        if any(menu_origin[i]<0 or menu_origin[i]+menu[i]*menu_scale>canvas[i]+1e-4 for i in range(2)):
            raise ValueError('Menu projection lies outside the actual canvas')
        safe=_numbers(state.get('canvas_safe_area'),4,'canvas_safe_area')
        if safe[0]<0 or safe[1]<0 or safe[2]<=0 or safe[3]<=0 or safe[0]+safe[2]>canvas[0]+1e-4 or safe[1]+safe[3]>canvas[1]+1e-4:
            raise ValueError('Canvas safe rectangle lies outside the actual canvas')
        geometry={'canvas':canvas,'battle':battle,'battle_origin':arena[:2],'battle_scale':scale,
                  'menu':menu,'menu_origin':menu_origin,'menu_scale':menu_scale}
    surface=_numbers(state.get('native_surface'),4,'native_surface')
    if surface[0]<0 or surface[1]<0 or surface[2]<=0 or surface[3]<=0:
        raise ValueError('Native surface must be a positive screen-space rectangle')
    geometry['surface']=surface
    return geometry

def canvas_steps(steps,space='canvas',state=None):
    """Convert explicitly named local pixels; never silently reinterpret old QA."""
    if space not in ['canvas','menu','battle']: raise ValueError('Unknown coordinate space')
    geometry=coordinate_geometry(state)
    extent=geometry['canvas'] if space=='canvas' else geometry[space]
    offset=[0,0] if space=='canvas' else geometry[space+'_origin']
    scale=1.0 if space=='canvas' else geometry[space+'_scale']
    result=copy.deepcopy(steps)
    def point(value):
        if not isinstance(value,list) or len(value)!=2: raise ValueError('A point needs x,y')
        if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or v<0 or v>extent[i] for i,v in enumerate(value)):
            raise ValueError('Point is outside the explicit coordinate space')
        return [value[i]*scale+offset[i] for i in range(2)]
    for step in result:
        if 'point' in step:step['point']=point(step['point'])
        for pointer in step.get('pointers',[]):pointer['point']=point(pointer['point'])
    return result

def touch_payload(state,sequence,steps,space='canvas'):
    geometry=coordinate_geometry(state)
    return {'sequence':sequence,'viewport':geometry['surface'],'native_size':geometry['canvas'],
            'steps':canvas_steps(steps,space,state)}

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

def command(session,steps,finish=False,space='canvas'):
    record=json.loads(session.read_text(encoding='utf-8')); serial=record['serial']; run_id=record['run_id']
    state=read_json(serial,'files/qa003a/'+run_id+'/state.json')
    record['sequence']+=1; sequence=record['sequence']
    data={'sequence':sequence,'finish':True} if finish else touch_payload(state,sequence,steps,space)
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
    global QA
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['init','state','capture','tap','drag','command','finish'])
    p.add_argument('--serial');p.add_argument('--session',type=Path);p.add_argument('--x',type=float);p.add_argument('--y',type=float);p.add_argument('--to-x',type=float);p.add_argument('--to-y',type=float);p.add_argument('--ms',type=int,default=700);p.add_argument('--label',default='capture');p.add_argument('--script',type=Path)
    p.add_argument('--space',choices=['canvas','menu','battle'],default='canvas',help='Explicit canvas pixels or authored640x360 menu/Battle pixels projected through actual reported origin and uniform scale')
    p.add_argument('--qa-task',default='003A.2',help='Explicit milestone output directory; Android debug protocol identity stays unchanged')
    args=p.parse_args()
    if not re.fullmatch(r'\d{3}[A-Z](?:\.\d+)*',args.qa_task):p.error('A bounded milestone task identity is required')
    QA=ROOT.parent/'GyroBrothers-QA'/args.qa_task
    for category in ['temp','manifests','images']:(QA/category).mkdir(parents=True,exist_ok=True)
    if args.mode=='init': result={'session':str(initialise(args.serial))}
    elif args.mode=='state':
        d=json.loads(args.session.read_text());result=read_json(d['serial'],'files/qa003a/'+d['run_id']+'/state.json')
    elif args.mode=='capture': result=capture(args.session,args.label)
    elif args.mode=='finish': result=command(args.session,[],True)
    elif args.mode=='command': result=command(args.session,json.loads(args.script.read_text(encoding='utf-8'))['steps'],space=args.space)
    else:
        steps=[{'type':'down','id':0,'point':[args.x,args.y],'ms':60}]
        if args.mode=='drag':steps.append({'type':'move','pointers':[{'id':0,'point':[args.to_x,args.to_y]}],'ms':args.ms,'samples':30})
        steps += [{'type':'up','id':0},{'type':'wait','ms':250}]
        result=command(args.session,steps,space=args.space)
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
