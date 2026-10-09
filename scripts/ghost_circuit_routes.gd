extends RefCounted
## Bounded, read-only indexing of visible paid Afterimage edges. Original trace
## ownership/cause is immutable; only precise used edge intervals are consumed.
const POINT_LIMIT: int = 224
const CONTINUITY: float = 26.0
const ATTACH: float = 8.0
var routes: Array[Dictionary] = []
var scanned_edges: int = 0
var candidate_edges: int = 0

func rebuild(traces: Array[Dictionary], now: float) -> void:
	routes.clear(); scanned_edges=0;candidate_edges=0
	var owners: Dictionary={}
	var ordered: Array[Dictionary]=traces.duplicate()
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if float(a.created_at)!=float(b.created_at):return float(a.created_at)<float(b.created_at)
		if int(a.owner_entity_id)!=int(b.owner_entity_id):return int(a.owner_entity_id)<int(b.owner_entity_id)
		return int(a.get("cause",{}).get("event_id",0))<int(b.get("cause",{}).get("event_id",0)))
	for trace: Dictionary in ordered:
		if float(trace.get("paid_rpm",0.0))<=0.0:continue
		if float(trace.get("expires_at",now+float(trace.get("life",0.0))))<=now or float(trace.get("life",0.0))<=0.0: continue
		var id: int=int(trace.owner_entity_id)
		if not owners.has(id):owners[id]=[]
		var points: Array=trace.get("points",[])
		for edge: int in range(points.size()-1):
			scanned_edges+=1
			var a: Vector2=points[edge];var b: Vector2=points[edge+1]
			if a.distance_squared_to(b)<0.01:continue
			var free: Array[Vector2]=[Vector2(0.0,1.0)]
			for used: Dictionary in trace.get("ghost_used_edges",[]):
				if int(used.edge)!=edge:continue
				var next: Array[Vector2]=[]
				for span: Vector2 in free:
					if float(used.hi)<=span.x or float(used.lo)>=span.y:next.append(span);continue
					if float(used.lo)>span.x:next.append(Vector2(span.x,float(used.lo)))
					if float(used.hi)<span.y:next.append(Vector2(float(used.hi),span.y))
				free=next
			for span: Vector2 in free:
				if span.y-span.x<0.0001:continue
				owners[id].append({"a":a.lerp(b,span.x),"b":a.lerp(b,span.y),"trace":trace,"edge":edge,"lo":span.x,"hi":span.y,"stamp":float(trace.created_at),"cut":span.x>0.0 or span.y<1.0})
	var ids: Array=owners.keys();ids.sort()
	for id: int in ids:
		var run: Array[Dictionary]=[]
		for piece: Dictionary in owners[id]:
			# A consumed interval is a real break, never a tolerable unpaid chord.
			if not run.is_empty() and (Vector2(run.back().b).distance_to(piece.a)>CONTINUITY or (run.back().trace==piece.trace and int(run.back().edge)==int(piece.edge)) or float(run.back().hi)<1.0 or float(piece.lo)>0.0):
				_finish(id,run);run=[]
			run.append(piece)
		_finish(id,run)

func _finish(id: int, pieces: Array[Dictionary]) -> void:
	if pieces.size()<2:return
	var points: Array[Vector2]=[pieces[0].a]
	var starts: Array[int]=[0]
	for index: int in range(pieces.size()):
		var point: Vector2=pieces[index].b
		if points.back().distance_to(point)>=3.0 or index==pieces.size()-1:
			points.append(point);starts.append(index+1)
	if points.size()>POINT_LIMIT:
		var trim: int=points.size()-POINT_LIMIT
		points=points.slice(trim);starts=starts.slice(trim)
	routes.append({"owner":id,"points":points,"starts":starts,"pieces":pieces,"stamp":float(pieces.back().stamp),"team":str(pieces[0].trace.team_id)})

func candidate(closer: Dictionary, previous: Vector2, now: float, preview: float, age: float, perimeter_min: float, area_min: float, extent: float, ratio: float, current: Array = []) -> Dictionary:
	var own: Array[Dictionary]=[]
	for run: Dictionary in routes:
		if int(run.owner)==int(closer.entity_id) and Vector2(run.points.back()).distance_to(closer.pos)<=6.0:own.append(run)
	var best: Dictionary={}
	for source: Dictionary in routes:
		var self_owned: bool=int(source.owner)==int(closer.entity_id)
		if not self_owned and (str(source.team)==str(closer.team_id) or str(source.team)=="neutral"):continue
		if self_owned:
			var self_points: Array[Vector2]=source.points.duplicate()
			if Vector2(source.points.back()).distance_to(closer.pos)>6.0:
				# The current connected buffer may preview a self closure. Runtime
				# activation still requires its actual paid visible emission.
				if current.is_empty() or self_points.back().distance_to(Vector2(current[0]))>CONTINUITY:continue
				for point: Vector2 in current:
					if self_points.back().distance_to(point)>=3.0:self_points.append(point)
			if self_points.back().distance_to(closer.pos)>6.0:continue
			var row: Dictionary=_evaluate(source,self_points,[],previous,closer,now,preview,age,perimeter_min,area_min,extent,ratio,false,Vector2.ZERO)
			if _better(row,best):best=row
		else:
			for bridge: Dictionary in own:
				var tail: Vector2=source.points.back()
				var first: int=-1;var socket: Vector2=Vector2.ZERO;var distance: float=ATTACH
				for index: int in range(bridge.pieces.size()):
					var piece: Dictionary=bridge.pieces[index]
					if float(piece.stamp)<float(source.stamp)-0.15:continue
					var near: Vector2=Geometry2D.get_closest_point_to_segment(tail,piece.a,piece.b)
					if tail.distance_to(near)<=distance:first=index;socket=near;distance=tail.distance_to(near)
				if first<0:continue
				var bridge_pieces: Array[Dictionary]=bridge.pieces.slice(first)
				bridge_pieces[0]=bridge_pieces[0].duplicate()
				var segment: Vector2=Vector2(bridge_pieces[0].b)-Vector2(bridge_pieces[0].a)
				var t: float=clampf((socket-Vector2(bridge_pieces[0].a)).dot(segment)/maxf(.0001,segment.length_squared()),0.0,1.0)
				bridge_pieces[0].lo=lerpf(float(bridge_pieces[0].lo),float(bridge_pieces[0].hi),t);bridge_pieces[0].a=socket
				var joined: Array[Vector2]=source.points.duplicate()
				var travel: float=0.0
				for piece: Dictionary in bridge_pieces:
					travel+=Vector2(piece.a).distance_to(piece.b)
					if joined.back().distance_to(piece.b)>=3.0:joined.append(piece.b)
				if travel<12.0:continue
				if joined.back().distance_to(closer.pos)>0.001:joined.append(closer.pos)
				var row: Dictionary=_evaluate(source,joined,bridge_pieces,previous,closer,now,preview,age,perimeter_min,area_min,extent,ratio,true,tail)
				if _better(row,best):best=row
	return best

func _evaluate(source: Dictionary, points: Array[Vector2], bridge: Array[Dictionary], previous: Vector2, closer: Dictionary, now: float, preview: float, age: float, perimeter_min: float, area_min: float, extent: float, ratio: float, hijack: bool, tail: Vector2) -> Dictionary:
	if points.size()<10 or points.size()>POINT_LIMIT+32:return {}
	var end: Vector2=closer.pos
	var best: Dictionary={}
	# Suffix sums make each eligibility calculation constant time. Only the
	# single winning route materialises its bounded polygon.
	var lengths: Array[float]=[];var crosses: Array[float]=[];var sums: Array[Vector2]=[];var boxes: Array[Rect2]=[]
	lengths.resize(points.size());crosses.resize(points.size());sums.resize(points.size());boxes.resize(points.size())
	for index: int in range(points.size()-1,-1,-1):
		if index==points.size()-1:lengths[index]=0.0;crosses[index]=0.0;sums[index]=points[index];boxes[index]=Rect2(points[index],Vector2.ZERO)
		else:lengths[index]=lengths[index+1]+points[index].distance_to(points[index+1]);crosses[index]=crosses[index+1]+points[index].cross(points[index+1]);sums[index]=sums[index+1]+points[index];boxes[index]=boxes[index+1].expand(points[index])
	var maximum: int=mini(points.size()-8,source.points.size()-1)
	for index: int in range(maximum):
		candidate_edges+=1
		if points.size()-index>POINT_LIMIT:continue
		var piece_index: int=int(source.starts[index])
		if now-float(source.pieces[piece_index].stamp)<age:continue
		var socket: Vector2=Geometry2D.get_closest_point_to_segment(end,points[index],points[index+1])
		# Locate the socket on an original paid edge, rather than the tiny
		# decimation chord. Its precise unused prefix remains available.
		var nearest: float=INF
		for native_edge: int in range(piece_index,mini(int(source.starts[index+1]),source.pieces.size())):
			var piece: Dictionary=source.pieces[native_edge]
			var at: Vector2=Geometry2D.get_closest_point_to_segment(socket,piece.a,piece.b)
			if at.distance_squared_to(socket)<nearest:nearest=at.distance_squared_to(socket);piece_index=native_edge
		var actual_piece: Dictionary=source.pieces[piece_index]
		if now-float(actual_piece.stamp)<age:continue
		socket=Geometry2D.get_closest_point_to_segment(end,actual_piece.a,actual_piece.b)
		var gap: float=socket.distance_to(end)
		if gap>preview:continue
		var crossing: Variant=Geometry2D.segment_intersects_segment(previous,end,actual_piece.a,actual_piece.b)
		var crossed: bool=crossing!=null
		if crossed:socket=crossing;gap=socket.distance_to(end)
		var perimeter: float=lengths[index+1]+socket.distance_to(points[index+1])+gap
		var area: float=absf(crosses[index+1]+socket.cross(points[index+1])+points.back().cross(socket))*.5
		var bounds: Rect2=boxes[index+1].expand(socket)
		if perimeter<perimeter_min or area<area_min or bounds.size.x<extent or bounds.size.y<extent or gap/perimeter>ratio:continue
		var progress: float=tail.distance_to(socket)-gap if hijack else INF
		var physically_closed: bool=not hijack or crossed or progress>=maxf(12.0,tail.distance_to(socket)*.60)
		var row: Dictionary={"route_owner":int(source.owner),"hijacked":hijack,"socket":socket,"gap":gap,"crossed":crossed,"physically_closed":physically_closed,"stamp":float(actual_piece.stamp),"center":(sums[index+1]+socket)/float(points.size()-index),"source":source,"index":index,"piece_index":piece_index,"bridge":bridge,"polygon_points":points,"perimeter":perimeter,"area":area,"physical_bridge_progress":progress}
		if _better(row,best):best=row
	if not best.is_empty():
		var polygon: PackedVector2Array=PackedVector2Array([best.socket]);polygon.append_array(PackedVector2Array(points.slice(int(best.index)+1)))
		best.polygon=polygon
	return best

func _better(row: Dictionary, best: Dictionary) -> bool:
	if row.is_empty():return false
	if best.is_empty():return true
	if bool(row.crossed)!=bool(best.crossed):return bool(row.crossed)
	if bool(row.physically_closed)!=bool(best.physically_closed):return bool(row.physically_closed)
	if not is_equal_approx(float(row.gap),float(best.gap)):return float(row.gap)<float(best.gap)
	if not is_equal_approx(float(row.stamp),float(best.stamp)):return float(row.stamp)>float(best.stamp)
	return int(row.route_owner)<int(best.route_owner)

## Prospective advice contains only an observable paid route's existing tail
## and socket. It cannot activate anything or know a future player path.
func observable_hint(closer: Dictionary, now: float, radius: float) -> Dictionary:
	var best: Dictionary={}
	for source: Dictionary in routes:
		if int(source.owner)==int(closer.entity_id) or str(source.team)==str(closer.team_id) or str(source.team)=="neutral":continue
		var tail: Vector2=source.points.back()
		if tail.distance_to(closer.pos)>radius:continue
		var probe: Dictionary=closer.duplicate();probe.pos=tail
		var row: Dictionary=_evaluate(source,source.points,[],tail,probe,now,70.0,.85,180.0,1300.0,32.0,.22,false,Vector2.ZERO)
		if row.is_empty() or float(row.gap)>56.0:continue
		if _better(row,best):best=row;best.tail=tail
	if best.is_empty():return {}
	var expires: float=now+.35
	for piece: Dictionary in best.source.pieces.slice(int(best.piece_index)):expires=minf(expires,float(piece.trace.expires_at))
	return {"route_owner_entity_id":best.route_owner,"tail":best.tail,"socket":best.socket,"expires_at":expires,"paid_visible_live":true}

func consume(candidate_row: Dictionary) -> Array[Dictionary]:
	var source: Dictionary=candidate_row.source
	var first: int=int(candidate_row.piece_index)
	var used: Array[Dictionary]=source.pieces.slice(first)
	used[0]=used[0].duplicate()
	var delta: Vector2=Vector2(used[0].b)-Vector2(used[0].a)
	var t: float=clampf((Vector2(candidate_row.socket)-Vector2(used[0].a)).dot(delta)/maxf(.0001,delta.length_squared()),0.0,1.0)
	used[0].lo=lerpf(float(used[0].lo),float(used[0].hi),t)
	used.append_array(candidate_row.bridge)
	for piece: Dictionary in used:
		var trace: Dictionary=piece.trace
		if not trace.has("ghost_used_edges"):trace.ghost_used_edges=[]
		var lo: float=float(piece.lo);var hi: float=float(piece.hi)
		for index: int in range(trace.ghost_used_edges.size()-1,-1,-1):
			var old: Dictionary=trace.ghost_used_edges[index]
			if int(old.edge)==int(piece.edge) and float(old.hi)>=lo and float(old.lo)<=hi:
				lo=minf(lo,float(old.lo));hi=maxf(hi,float(old.hi));trace.ghost_used_edges.remove_at(index)
		trace.ghost_used_edges.append({"edge":int(piece.edge),"lo":lo,"hi":hi})
	return used
