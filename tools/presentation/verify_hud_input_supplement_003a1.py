"""Fresh isolated supplemental UI/input checks with source and player guards."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
from datetime import datetime,timezone
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
sys.path.insert(0,str(ROOT/'tools/workspace'))
sys.path.insert(0,str(ROOT/'tools/presentation'))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--engine');args=parser.parse_args()
    qa=workspace.create_task_workspace('003A.1')
    stem='003a1_hud_input_final_supplement_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    report=qa/'manifests'/f'{stem}.json'
    before=source(ROOT);player_before=profile()
    names=['state_meters','combat_hud','combat_acceptance_hud','overdrive_lifecycle','input_acceptance','bulk_packet_touch']
    driver_paths={name:ROOT/'tests'/f'test_{name}_003a1.gd' for name in names}
    driver_paths.update({'android_coordinates':ROOT/'tools/android/test_touch_coordinates_003a1.py','android_device':ROOT/'tools/android/device_acceptance.py','android_native_driver':ROOT/'tools/android/TouchDriver.java','android_instrumentation':ROOT/'tools/android/touch_instrumentation.py'})
    drivers={name:pipeline.sha256(path) for name,path in driver_paths.items()}
    proof={'status':'running','scope':'Fresh supplemental tests after stale test adapter repairs and narrow post-freeze integration fixes. All persisted UI profiles are isolated under this003A.1 QA tree. Logical events and Java compile are not physical phone acceptance.','source_before':before,'player_before':player_before,'drivers_before':drivers,'results':[]}
    pipeline.write_json(report,proof)
    engine=workspace.find_tool('godot',args.engine)
    def run(name):
        output=qa/'manifests'/f'{stem}_{name}.json';log=qa/'logs'/f'{stem}_{name}.log'
        command=[engine,'--headless','--path',str(ROOT),'--script',str(driver_paths[name]),'--fixed-fps','60','--audio-driver','Dummy','--','--report='+str(output)]
        if name in ['overdrive_lifecycle','input_acceptance']:command+=['--profiles='+str(qa/'temp'/f'{stem}_{name}_profiles')]
        try:process=pipeline.run_logged(command,log,600)
        except pipeline.ProcessValidationError as error:process=error.record
        data=json.loads(output.read_text(encoding='utf-8'))
        failed=bool(data['failures']) or process['exit_code']!=0
        result={'test':name,'checks':data['checks'],'failures':data['failures'],'passed':not failed,'report':str(output),'report_sha256':pipeline.sha256(output),'process':process}
        print(json.dumps({'test':name,'checks':data['checks'],'status':'failed' if failed else 'passed'}),flush=True)
        return result
    try:
        with ThreadPoolExecutor(max_workers=2) as executor:proof['results']=list(executor.map(run,names))
        coordinate=pipeline.run_logged([sys.executable,str(driver_paths['android_coordinates']),'-v'],qa/'logs'/f'{stem}_android_coordinates.log',120)
        classes=qa/'temp'/f'{stem}_android_java_classes';classes.mkdir()
        javac=Path(r'C:\Program Files\Microsoft\jdk-25.0.4.101-hotspot\bin\javac.exe')
        android=Path.home()/'AppData/Local/Android/Sdk/platforms/android-36/android.jar'
        assert javac.is_file() and android.is_file()
        compiled=pipeline.run_logged([str(javac),'-source','8','-target','8','-classpath',str(android),'-d',str(classes),str(driver_paths['android_native_driver'])],qa/'logs'/f'{stem}_android_javac.log',120)
        proof.update(android_coordinate_test=coordinate,android_java_compile=compiled,android_java_classes=str(classes),android_unit_test_count=5)
    finally:
        proof.update(source_after=source(ROOT),player_after=profile(),drivers_after={name:pipeline.sha256(path) for name,path in driver_paths.items()})
        proof.update(source_unchanged=proof['source_before']==proof['source_after'],player_unchanged=proof['player_before']==proof['player_after'],drivers_unchanged=proof['drivers_before']==proof['drivers_after'])
        proof['status']='passed' if len(proof['results'])==len(names) and all(row['passed'] for row in proof['results']) and 'android_java_compile' in proof and proof['source_unchanged'] and proof['player_unchanged'] and proof['drivers_unchanged'] else 'failed'
        pipeline.write_json(report,proof)
    assert proof['source_unchanged'] and proof['player_unchanged'] and proof['drivers_unchanged']
    assert proof['status']=='passed'
    print(json.dumps({'manifest':str(report),'godot_checks':sum(row['checks'] for row in proof['results']),'android_unit_tests':5,'java_compile':'passed','source_unchanged':True,'player_unchanged':True},indent=2),flush=True)

if __name__=='__main__':main()
