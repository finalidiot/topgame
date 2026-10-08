"""Guard explicit product/menu/Battle coordinate spaces without a device."""
from __future__ import annotations
import copy
import importlib.util
from pathlib import Path
import unittest

MODULE=Path(__file__).with_name('device_acceptance.py')
spec=importlib.util.spec_from_file_location('acceptance_device_coordinates',MODULE)
device=importlib.util.module_from_spec(spec)
spec.loader.exec_module(device)

class TouchCoordinates(unittest.TestCase):
    def state(self):
        return {'viewport':[800,480],'combat_viewport':[640,360],'arena_origin':[80,60],'native_surface':[120,60,1600,960]}

    def test_canvas_action_rail_and_product_corners(self):
        steps=[{'type':'down','id':1,'point':[759,320]},{'type':'move','pointers':[{'id':1,'point':[0,0]},{'id':2,'point':[800,480]}]}]
        original=copy.deepcopy(steps)
        payload=device.touch_payload(self.state(),1,steps)
        self.assertEqual(payload['steps'],steps)
        self.assertEqual(payload['native_size'],[800,480])
        self.assertEqual(payload['viewport'],[120,60,1600,960])
        self.assertEqual(steps,original)

    def test_menu_origin_and_outer_packets(self):
        for point in [[0,0],[640,360],[156,190],[484,190]]:
            with self.subTest(point=point):
                payload=device.touch_payload(self.state(),2,[{'type':'down','id':0,'point':point}],'menu')
                self.assertEqual(payload['steps'][0]['point'],[point[0]+80,point[1]+60])

    def test_battle_projection_and_independent_fingers(self):
        steps=[{'type':'move','pointers':[{'id':0,'point':[320,165]},{'id':1,'point':[100,230]}]},{'type':'up','id':1}]
        payload=device.touch_payload(self.state(),3,steps,'battle')
        self.assertEqual(payload['steps'][0]['pointers'],[{'id':0,'point':[400,225]},{'id':1,'point':[180,290]}])
        self.assertEqual(payload['steps'][1],steps[1])
        self.assertEqual(steps[0]['pointers'][0]['point'],[320,165])

    def test_old_canvas_or_wrong_world_schema_is_refused(self):
        for key,value in [('viewport',[640,360]),('combat_viewport',[800,480]),('arena_origin',[0,0])]:
            state=self.state();state[key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):device.touch_payload(state,4,[])

    def test_each_coordinate_space_retains_its_own_bounds(self):
        for space,point in [('canvas',[801,320]),('canvas',[320,481]),('menu',[641,180]),('battle',[180,361]),('menu',[-1,180]),('battle',[True,180]),('canvas',[float('nan'),100]),('canvas',[100,float('inf')])]:
            with self.subTest(space=space,point=point),self.assertRaises(ValueError):device.canvas_steps([{'point':point}],space)
        with self.assertRaises(ValueError):device.canvas_steps([],'legacy_640')

if __name__=='__main__':unittest.main()
