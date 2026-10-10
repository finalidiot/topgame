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
DRIVER_MODULE=Path(__file__).with_name('touch_instrumentation.py')
driver_spec=importlib.util.spec_from_file_location('acceptance_native_coordinates',DRIVER_MODULE)
driver=importlib.util.module_from_spec(driver_spec)
driver_spec.loader.exec_module(driver)

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

    def fullscreen_state(self):
        return {'viewport':[1204,540],'canvas_size':[1204,540],
                'combat_viewport':[640,360],'arena_origin':[234,70],
                'arena_rect':[234,70,736,414],'arena_scale':1.15,
                'menu_native_view':[640,360],'menu_origin':[282,90],'menu_scale':1.0,
                'canvas_safe_area':[24,0,1170,540],'native_surface':[0,0,2408,1080]}

    def test_fullscreen_canvas_uses_actual_extent_and_keeps_input_immutable(self):
        state=self.fullscreen_state();steps=[{'type':'down','id':2,'point':[1180,430]},
            {'type':'move','pointers':[{'id':0,'point':[1204,540]},{'id':2,'point':[24,0]}]}]
        original=copy.deepcopy(steps)
        payload=device.touch_payload(state,5,steps)
        self.assertEqual(payload['native_size'],[1204,540])
        self.assertEqual(payload['viewport'],[0,0,2408,1080])
        self.assertEqual(payload['steps'],steps)
        self.assertEqual(steps,original)

    def test_fullscreen_battle_maps_canonical_world_with_uniform_scale(self):
        state=self.fullscreen_state()
        for point in [[0,0],[640,360],[320,180]]:
            payload=device.touch_payload(state,6,[{'point':point}],'battle')
            for actual,expected in zip(payload['steps'][0]['point'],[point[0]*1.15+234,point[1]*1.15+70]):
                self.assertAlmostEqual(actual,expected)
        with self.assertRaises(ValueError):device.canvas_steps([{'point':[641,180]}],'battle',state)

    def test_menu_has_its_own_origin_and_uniform_scale(self):
        state=self.fullscreen_state();state['menu_scale']=1.2;state['menu_origin']=[220,30]
        payload=device.touch_payload(state,7,[{'point':[156,190]}],'menu')
        self.assertEqual(payload['steps'][0]['point'],[407.2,258.0])
        self.assertNotEqual(payload['steps'][0]['point'],device.touch_payload(state,7,[{'point':[156,190]}],'battle')['steps'][0]['point'])

    def test_fractional_physical_overscan_preserves_logical_canvas(self):
        state=self.fullscreen_state();state['native_surface']=[0,0,2409,1080]
        payload=device.touch_payload(state,8,[{'point':[1204,540]}])
        self.assertEqual(payload['steps'][0]['point'],[1204,540])
        self.assertEqual(payload['viewport'],[0,0,2409,1080])

    def test_partial_or_nonuniform_fullscreen_geometry_is_refused(self):
        invalid=[('canvas_size',[True,540]),('canvas_size',[float('nan'),540]),('canvas_size',[10000,540]),
                 ('viewport',[800,480]),('combat_viewport',[800,480]),('arena_origin',[0,0]),
                 ('arena_rect',[234,70,736,413]),('arena_scale',0),('arena_scale',float('inf')),
                 ('menu_native_view',[800,480]),('menu_origin',[1000,0]),('menu_scale',-1),
                 ('canvas_safe_area',[24,0,1204,540]),('native_surface',[0,0,0,1080])]
        for key,value in invalid:
            state=self.fullscreen_state();state[key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):device.touch_payload(state,9,[])
        for key in ['arena_rect','arena_scale','menu_origin','menu_scale','canvas_safe_area']:
            state=self.fullscreen_state();del state[key]
            with self.subTest(missing=key),self.assertRaises(ValueError):device.touch_payload(state,10,[])

    def test_unknown_coordinate_space_and_fullscreen_canvas_bounds_are_refused(self):
        state=self.fullscreen_state()
        for point in [[1205,400],[600,541],[-1,1],[100,float('nan')],[False,100]]:
            with self.subTest(point=point),self.assertRaises(ValueError):device.canvas_steps([{'point':point}],'canvas',state)
        with self.assertRaises(ValueError):device.canvas_steps([],'screen',state)

    def test_native_wrapper_accepts_legacy_and_dynamic_canvas_without_reinterpretation(self):
        for size in [[800,480],[854,480],[1204,540],[1067,800],[8192,8192]]:
            self.assertEqual(driver.native_canvas_size(size),size)
            self.assertIsNot(driver.native_canvas_size(size),size)

    def test_native_wrapper_refuses_malformed_nonfinite_or_unbounded_canvas(self):
        for size in [None,[],[800],[True,480],[float('nan'),480],[800,float('inf')],[0,480],[-1,480],[8193,480],['800',480]]:
            with self.subTest(size=size),self.assertRaises(ValueError):driver.native_canvas_size(size)

if __name__=='__main__':unittest.main()
