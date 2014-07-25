/*
	This program is free software; you can redistribute it and/or modify it 
	under the terms of the GNU General Public License as published by the 
	Free Software Foundation; either version 2, or (at your option) any later
	version.
	
	This program is distributed in the hope that it will be useful, but 
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
	Public License for more details.

	You should have received a copy of the GNU General Public License along
	with this program; if not, write to the Free Software Foundation, Inc.,
	59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.
	
	Copyright (C) 2001-2010 Peter Selinger (Original author)
	Copyright (C) 2009 Wolfgang Nagl (C# port of Potrace 1.8: "Vectorization")
	Copyright (C) 2011 Claus Wahlers (AS3 port of Vectorization: "as3potrace")
	
	"Potrace" is a trademark of Peter Selinger. "Potrace Professional" and
	"Icosasoft" are trademarks of Icosasoft Software Inc. Other trademarks
	belong to their respective owners.
	
	http://potrace.sourceforge.net/
	http://www.drawing3d.de/Downloads.aspx (Vectorization)
	https://github.com/Poweropenfl.rBR/as3potrace (as3potrace)
*/

package potrace;

import potrace.POTraceParams;

import potrace.backend.IBackend;
import potrace.backend.NullBackend;
import potrace.geom.Curve;
import potrace.geom.CurveKind;
import potrace.geom.Direction;
import potrace.geom.MonotonInterval;
import potrace.geom.Opti;
import potrace.geom.Path;
import potrace.geom.PointInt;
import potrace.geom.PrivCurve;
import potrace.geom.SumStruct;

import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.Vector;

class POTrace
{
    public var params(get, set) : POTraceParams;
    public var backend(get, set) : IBackend;

    private var bmWidth : Int;
    private var bmHeight : Int;
    
    private var _params : POTraceParams;
    private var _backend : IBackend;
    
    private static inline var POTRACE_CORNER : Int = 1;
    private static inline var POTRACE_CURVETO : Int = 2;
    
    private static var COS179 : Float = Math.cos(179 * Math.PI / 180);
    
    public function new(params : POTraceParams = null, backend : IBackend = null)
    {
        _params = params || new POTraceParams();
        _backend = backend || new NullBackend();
    }
    
    private function get_Params() : POTraceParams{
        return _params;
    }
    private function set_Params(params : POTraceParams) : POTraceParams{
        _params = params;
        return params;
    }
    
    private function get_Backend() : IBackend{
        return _backend;
    }
    private function set_Backend(backend : IBackend) : IBackend{
        _backend = backend;
        return backend;
    }
    
    /*
		 * Main function
		 * Yields the curve informations related to a given binary bitmap.
		 * Returns an array of curvepaths. 
		 * Each of this paths is a list of connecting curves.
		 */
    public function potrace_trace(bitmapData : BitmapData) : Array<Array<Array<Curve>>>
    {
        // Make sure there is a 1px white border
        var bitmapDataCopy : BitmapData = new BitmapData(bitmapData.width + 2, bitmapData.height + 2, false, 0xffffff);
        bitmapDataCopy.threshold(bitmapData, bitmapData.rect, new Point(1, 1), params.thresholdOperator, params.threshold, 0x000000, 0xffffff, false);
        
        this.bmWidth = bitmapDataCopy.width;
        this.bmHeight = bitmapDataCopy.height;
        
        var i : Int;
        var j : Int;
        var k : Int;
        var pos : Int = 0;
        
        var bitmapDataVecTmp : Vector<Int> = bitmapDataCopy.getVector(bitmapDataCopy.rect);
        var bitmapDataMatrix : Vector<Vector<Int>> = new Vector<Vector<Int>>(bmHeight);
        
        for (i in 0...bmHeight){
            var row : Vector<Int> = bitmapDataVecTmp.substring(pos, pos + bmWidth);
            for (j in 0...row.length){
                row[j] &= 0xffffff;
            }
            bitmapDataMatrix[i] = row;
            pos += bmWidth;
        }
        
        var plists : Array<Array<Path>> = bm_to_pathlist(bitmapDataMatrix);
        
        process_path(plists);
        
        var shapes : Array<Array<Array<Curve>>> = pathlist_to_curvearrayslist(plists);
        
        if (backend != null) 
        {
            backend.init(bmWidth, bmHeight);
            
            for (i in 0...shapes.length){
                backend.initShape();
                var shape : Array<Array<Curve>> = shapes[i];
                for (j in 0...shape.length){
                    backend.initSubShape((j % 2) == 0);
                    var curves : Array<Curve> = shape[j];
                    if (curves.length > 0) {
                        var curve : Curve = curves[0];
                        backend.moveTo(curve.a.clone());
                        for (k in 0...curves.length){
                            curve = curves[k];
                            var _sw0_ = (curve.kind);                            

                            switch (_sw0_)
                            {
                                case CurveKind.BEZIER:
                                    backend.addBezier(
                                            curve.a.clone(),
                                            curve.cpa.clone(),
                                            curve.cpb.clone(),
                                            curve.b.clone()
                                            );
                                case CurveKind.LINE:
                                    backend.addLine(
                                            curve.a.clone(),
                                            curve.b.clone()
                                            );
                            }
                        }
                    }
                    backend.exitSubShape();
                }
                backend.exitShape();
            }
            
            backend.exit();
        }
        
        return shapes;
    }
    
    /*
		 * Decompose the given bitmap into paths. Returns a list of
		 * Path objects with the fields len, pt, area filled
		 */
    private function bm_to_pathlist(bitmapDataMatrix : Vector<Vector<Int>>) : Array<Array<Path>>
    {
        var plists : Array<Array<Path>> = new Array<Array<Path>>();
        var pt : PointInt;
        while ((pt = find_next(bitmapDataMatrix)) != null){
            get_contour(bitmapDataMatrix, pt, plists);
        }
        return plists;
    }
    
    /*
		 * Searches a point such that source[x, y] = true and source[x+1, y] = false.
		 * If this not exists, null will be returned, else the result is Point(x, y).
		 */
    private function find_next(bitmapDataMatrix : Vector<Vector<Int>>) : PointInt
    {
        var x : Int;
        var y : Int;
        for (y in 1...bmHeight - 1){
            for (x in 0...bmWidth - 1){
                if (bitmapDataMatrix[y][x + 1] == 0) {
                    // Black found
                    return new PointInt(x, y);
                }
            }
        }
        return null;
    }
    
    private function get_contour(bitmapDataMatrix : Vector<Vector<Int>>, pt : PointInt, plists : Array<Array<Path>>) : Void
    {
        var plist : Array<Path> = new Array<Path>();
        
        var path : Path = find_path(bitmapDataMatrix, pt);
        
        xor_path(bitmapDataMatrix, path);
        
        // Only area > turdsize is taken
        if (path.area > params.turdSize) {
            // Path with index 0 is a contour
            plist.push(path);
            plists.push(plist);
        }
        
        while ((pt = find_next_in_path(bitmapDataMatrix, path)) != null)
        {
            var hole : Path = find_path(bitmapDataMatrix, pt);
            
            xor_path(bitmapDataMatrix, hole);
            
            if (hole.area > params.turdSize) {
                // Path with index > 0 is a hole
                plist.push(hole);
            }
            
            if ((pt = find_next_in_path(bitmapDataMatrix, hole)) != null) {
                get_contour(bitmapDataMatrix, pt, plists);
            }
        }
    }
    
    /*
		 * Compute a path in the binary matrix.
		 * 
		 * Start path at the point (x0,x1), which must be an upper left corner
		 * of the path. Also compute the area enclosed by the path. Return a
		 * new path_t object, or NULL on error (note that a legitimate path
		 * cannot have length 0).
		 * 
		 * We omit turnpolicies and sign
		 */
    private function find_path(bitmapDataMatrix : Vector<Vector<Int>>, start : PointInt) : Path
    {
        var l : Vector<PointInt> = new Vector<PointInt>();
        var p : PointInt = start.clone();
        var dir : Int = Direction.NORTH;
        var area : Int = 0;
        
        do
        {
            l.push(p.clone());
            var _y : Int = p.y;
            dir = find_next_trace(bitmapDataMatrix, p, dir);
            area += p.x * (_y - p.y);
        }        while (((p.x != start.x) || (p.y != start.y)));
        
        if (l.length == 0) {
            return null;
        }
        
        var result : Path = new Path();
        result.area = area;
        result.pt = new Vector<PointInt>(l.length);
        for (i in 0...l.length){
            result.pt[i] = l[i];
        }  // Shift 1 to be compatible with Potrace  
        
        
        
        if (result.pt.length > 1) {
            result.pt.unshift(result.pt.pop());
        }
        
        result.monotonIntervals = get_monoton_intervals(result.pt);
        
        return result;
    }
    
    /*
		 * Searches a point inside a path such that source[x, y] = true and source[x+1, y] = false.
		 * If this not exists, null will be returned, else the result is Point(x, y).
		 */
    private function find_next_in_path(bitmapDataMatrix : Vector<Vector<Int>>, path : Path) : PointInt
    {
        if (path.monotonIntervals.length == 0) {
            return null;
        }
        
        var i : Int = 0;
        var n : Int = path.pt.length;
        
        var mis : Vector<MonotonInterval> = path.monotonIntervals;
        var mi : MonotonInterval = mis[0];
        mi.resetCurrentId(n);
        
        var y : Int = path.pt[mi.currentId].y;
        
        var currentIntervals : Vector<MonotonInterval> = new Vector<MonotonInterval>();
        currentIntervals[0] = mi;
        
        mi.currentId = mi.min();
        
        while ((mis.length > i + 1) && (mis[i + 1].minY(path.pt) == y))
        {
            mi = mis[i + 1];
            mi.resetCurrentId(n);
            currentIntervals.push(mi);
            i++;
        }
        
        while (currentIntervals.length > 0)
        {
            var j : Int;
            
            for (k in 0...currentIntervals.length - 1){
                var x1 : Int = path.pt[currentIntervals[k].currentId].x + 1;
                var x2 : Int = path.pt[currentIntervals[k + 1].currentId].x;
                for (x in x1...x2 + 1){
                    if (bitmapDataMatrix[y][x] == 0) {
                        return new PointInt(x - 1, y);
                    }
                }
                k++;
            }
            
            y++;
            j = currentIntervals.length - 1;
            while (j >= 0){
                var m : MonotonInterval = currentIntervals[j];
                if (y > m.maxY(path.pt)) {
                    currentIntervals.splice(j, 1);
                    {j--;continue;
                    }
                }
                var cid : Int = m.currentId;
                do
                {
                    cid = (m.increasing) ? mod(cid + 1, n) : mod(cid - 1, n);
                }                while ((path.pt[cid].y < y));
                m.currentId = cid;
                j--;
            }  // Add Items of MonotonIntervals with Down.y==y  
            
            
            
            while ((mis.length > i + 1) && (mis[i + 1].minY(path.pt) == y))
            {
                var newInt : MonotonInterval = mis[i + 1];
                // Search the correct x position
                j = 0;
                var _x : Int = path.pt[newInt.min()].x;
                while ((currentIntervals.length > j) && (_x > path.pt[currentIntervals[j].currentId].x)){
                    j++;
                }
                currentIntervals.splice(j, 0, newInt);
                newInt.resetCurrentId(n);
                i++;
            }
        }
        return null;
    }
    
    private function xor_path(bitmapDataMatrix : Vector<Vector<Int>>, path : Path) : Void
    {
        if (path.monotonIntervals.length == 0) {
            return;
        }
        
        var i : Int = 0;
        var n : Int = path.pt.length;
        
        var mis : Vector<MonotonInterval> = path.monotonIntervals;
        var mi : MonotonInterval = mis[0];
        mi.resetCurrentId(n);
        
        var y : Int = path.pt[mi.currentId].y;
        var currentIntervals : Vector<MonotonInterval> = new Vector<MonotonInterval>();
        currentIntervals.push(mi);
        
        mi.currentId = mi.min();
        
        while ((mis.length > i + 1) && (mis[i + 1].minY(path.pt) == y))
        {
            mi = mis[i + 1];
            mi.resetCurrentId(n);
            currentIntervals.push(mi);
            i++;
        }
        
        while (currentIntervals.length > 0)
        {
            var j : Int;
            
            for (k in 0...currentIntervals.length - 1){
                var x1 : Int = path.pt[currentIntervals[k].currentId].x + 1;
                var x2 : Int = path.pt[currentIntervals[k + 1].currentId].x;
                for (x in x1...x2 + 1){
                    // Invert pixel
                    bitmapDataMatrix[y][x] ^= 0xffffff;
                }
                k++;
            }
            
            y++;
            j = currentIntervals.length - 1;
            while (j >= 0){
                var m : MonotonInterval = currentIntervals[j];
                if (y > m.maxY(path.pt)) {
                    currentIntervals.splice(j, 1);
                    {j--;continue;
                    }
                }
                var cid : Int = m.currentId;
                do
                {
                    cid = (m.increasing) ? mod(cid + 1, n) : mod(cid - 1, n);
                }                while ((path.pt[cid].y < y));
                m.currentId = cid;
                j--;
            }  // Add Items of MonotonIntervals with Down.y==y  
            
            
            
            while ((mis.length > i + 1) && (mis[i + 1].minY(path.pt) == y))
            {
                var newInt : MonotonInterval = mis[i + 1];
                // Search the correct x position
                j = 0;
                var _x : Int = path.pt[newInt.min()].x;
                while ((currentIntervals.length > j) && (_x > path.pt[currentIntervals[j].currentId].x)){
                    j++;
                }
                currentIntervals.splice(j, 0, newInt);
                newInt.resetCurrentId(n);
                i++;
            }
        }
    }
    
    private function get_monoton_intervals(pt : Vector<PointInt>) : Vector<MonotonInterval>
    {
        var result : Vector<MonotonInterval> = new Vector<MonotonInterval>();
        var n : Int = pt.length;
        if (n == 0) {
            return result;
        }
        
        var intervals : Vector<MonotonInterval> = new Vector<MonotonInterval>();
        
        // Start with Strong Monoton (Pts[i].y < Pts[i+1].y) or (Pts[i].y > Pts[i+1].y)
        var firstStrongMonoton : Int = 0;
        while (pt[firstStrongMonoton].y == pt[firstStrongMonoton + 1].y){
            firstStrongMonoton++;
        }
        
        var i : Int = firstStrongMonoton;
        var up : Bool = (pt[firstStrongMonoton].y < pt[firstStrongMonoton + 1].y);
        var interval : MonotonInterval = new MonotonInterval(up, firstStrongMonoton, firstStrongMonoton);
        intervals.push(interval);
        
        do
        {
            var i1n : Int = mod(i + 1, n);
            if ((pt[i].y == pt[i1n].y) || (up == (pt[i].y < pt[i1n].y))) {
                interval.to = i;
            }
            else {
                up = (pt[i].y < pt[i1n].y);
                interval = new MonotonInterval(up, i, i);
                intervals.push(interval);
            }
            i = i1n;
        }        while ((i != firstStrongMonoton));
        
        if ((intervals.length & 1) == 1) {
            var last : MonotonInterval = intervals.pop();
            intervals[0].from = last.from;
        }
        
        while (intervals.length > 0)
        {
            i = 0;
            var m : MonotonInterval = intervals.shift();
            while ((i < result.length) && (pt[m.min()].y > pt[result[i].min()].y)){
                i++;
            }
            while ((i < result.length) && (pt[m.min()].y == pt[result[i].min()].y) && (pt[m.min()].x > pt[result[i].min()].x)){
                i++;
            }
            result.splice(i, 0, m);
        }
        
        return result;
    }
    
    private function find_next_trace(bitmapDataMatrix : Vector<Vector<Int>>, p : PointInt, dir : Int) : Int
    {
        switch (dir)
        {
            case Direction.WEST:
                if (bitmapDataMatrix[p.y + 1][p.x + 1] == 0) {
                    dir = Direction.NORTH;
                    p.y++;
                }
                else {
                    if (bitmapDataMatrix[p.y][p.x + 1] == 0) {
                        dir = Direction.WEST;
                        p.x++;
                    }
                    else {
                        dir = Direction.SOUTH;
                        p.y--;
                    }
                }
            
            case Direction.SOUTH:
                if (bitmapDataMatrix[p.y][p.x + 1] == 0) {
                    dir = Direction.WEST;
                    p.x++;
                }
                else {
                    if (bitmapDataMatrix[p.y][p.x] == 0) {
                        dir = Direction.SOUTH;
                        p.y--;
                    }
                    else {
                        dir = Direction.EAST;
                        p.x--;
                    }
                }
            
            case Direction.EAST:
                if (bitmapDataMatrix[p.y][p.x] == 0) {
                    dir = Direction.SOUTH;
                    p.y--;
                }
                else {
                    if (bitmapDataMatrix[p.y + 1][p.x] == 0) {
                        dir = Direction.EAST;
                        p.x--;
                    }
                    else {
                        dir = Direction.NORTH;
                        p.y++;
                    }
                }
            
            case Direction.NORTH:
                if (bitmapDataMatrix[p.y + 1][p.x] == 0) {
                    dir = Direction.EAST;
                    p.x--;
                }
                else {
                    if (bitmapDataMatrix[p.y + 1][p.x + 1] == 0) {
                        dir = Direction.NORTH;
                        p.y++;
                    }
                    else {
                        dir = Direction.WEST;
                        p.x++;
                    }
                }
        }
        return dir;
    }
    
    private function process_path(plists : Array<Array<Path>>) : Void
    {
        // call downstream function with each path
        for (j in 0...plists.length){
            var plist : Array<Path> = plists[j];
            for (i in 0...plist.length){
                var path : Path = plist[i];
                calc_sums(path);
                calc_lon(path);
                bestpolygon(path);
                adjust_vertices(path);
                smooth(path.curves, 1, params.alphaMax);
                if (params.curveOptimizing) {
                    opticurve(path, params.optTolerance);
                    path.fCurves = path.optimizedCurves;
                }
                else {
                    path.fCurves = path.curves;
                }
                path.curves = path.fCurves;
            }
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // PREPARATION
    /////////////////////////////////////////////////////////////////////////
    
    /*
		 * Fill in the sum* fields of a path (used for later rapid summing)
		 */
    private function calc_sums(path : Path) : Void
    {
        var n : Int = path.pt.length;
        
        // Origin
        var x0 : Int = path.pt[0].x;
        var y0 : Int = path.pt[0].y;
        
        path.sums = new Vector<SumStruct>(n + 1);
        
        var ss : SumStruct = new SumStruct();
        ss.x2 = ss.xy = ss.y2 = ss.x = ss.y = 0;
        path.sums[0] = ss;
        
        for (i in 0...n){
            var x : Int = path.pt[i].x - x0;
            var y : Int = path.pt[i].y - y0;
            ss = new SumStruct();
            ss.x = path.sums[i].x + x;
            ss.y = path.sums[i].y + y;
            ss.x2 = path.sums[i].x2 + x * x;
            ss.xy = path.sums[i].xy + x * y;
            ss.y2 = path.sums[i].y2 + y * y;
            path.sums[i + 1] = ss;
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // STAGE 1
    // determine the straight subpaths (Sec. 2.2.1).
    /////////////////////////////////////////////////////////////////////////
    
    /*
		 * Fill in the "lon" component of a path object (based on pt/len).
		 * For each i, lon[i] is the furthest index such that a straight line 
		 * can be drawn from i to lon[i].
		 * 
		 * This algorithm depends on the fact that the existence of straight
		 * subpaths is a triplewise property. I.e., there exists a straight
		 * line through squares i0,...,in if there exists a straight line
		 * through i,j,k, for all i0 <= i < j < k <= in. (Proof?)
		 */
    private function calc_lon(path : Path) : Void
    {
        var i : Int;
        var j : Int;
        var k : Int;
        var k1 : Int;
        var a : Int;
        var b : Int;
        var c : Int;
        var d : Int;
        var dir : Int;
        var ct : Vector<Int> = new Vector<Int>(4);
        var constraint : Vector<PointInt> = new Vector<PointInt>(2);
        constraint[0] = new PointInt();
        constraint[1] = new PointInt();
        var cur : PointInt = new PointInt();
        var off : PointInt = new PointInt();
        var dk : PointInt = new PointInt();  // direction of k - k1  
        var pt : Vector<PointInt> = path.pt;
        
        var n : Int = pt.length;
        var pivot : Vector<Int> = new Vector<Int>(n);
        var nc : Vector<Int> = new Vector<Int>(n);
        
        // Initialize the nc data structure. Point from each point to the
        // furthest future point to which it is connected by a vertical or
        // horizontal segment. We take advantage of the fact that there is
        // always a direction change at 0 (due to the path decomposition
        // algorithm). But even if this were not so, there is no harm, as
        // in practice, correctness does not depend on the word "furthest"
        // above.
        
        k = 0;
        i = n - 1;
        while (i >= 0){
            if (pt[i].x != pt[k].x && pt[i].y != pt[k].y) {
                k = i + 1;
            }
            nc[i] = k;
            i--;
        }
        
        path.lon = new Vector<Int>(n);
        
        // Determine pivot points:
        // for each i, let pivot[i] be the furthest k such that
        // all j with i < j < k lie on a line connecting i,k
        
        i = n - 1;
        while (i >= 0){
            ct[0] = ct[1] = ct[2] = ct[3] = 0;
            
            // Keep track of "directions" that have occurred
            dir = (3 + 3 * (pt[mod(i + 1, n)].x - pt[i].x) + (pt[mod(i + 1, n)].y - pt[i].y)) / 2;
            ct[dir % 4]++;
            
            constraint[0].x = 0;
            constraint[0].y = 0;
            constraint[1].x = 0;
            constraint[1].y = 0;
            
            // Find the next k such that no straight line from i to k
            k = nc[i];
            k1 = i;
            
            var foundk : Bool = false;
            while (true)
            {
                dir = (3 + 3 * sign(pt[k].x - pt[k1].x) + sign(pt[k].y - pt[k1].y)) / 2;
                ct[dir]++;
                
                // If all four "directions" have occurred, cut this path
                if ((ct[0] >= 1) && (ct[1] >= 1) && (ct[2] >= 1) && (ct[3] >= 1)) {
                    pivot[i] = k1;
                    foundk = true;
                    break;
                }
                
                cur.x = pt[k].x - pt[i].x;
                cur.y = pt[k].y - pt[i].y;
                
                // See if current constraint is violated
                if (xprod(constraint[0], cur) < 0 || xprod(constraint[1], cur) > 0) {
                    break;
                }
                
                if (abs(cur.x) <= 1 && abs(cur.y) <= 1) {
                    // no constraint
                    
                }
                else {
                    off.x = cur.x + (((cur.y >= 0 && (cur.y > 0 || cur.x < 0))) ? 1 : -1);
                    off.y = cur.y + (((cur.x <= 0 && (cur.x < 0 || cur.y < 0))) ? 1 : -1);
                    if (xprod(constraint[0], off) >= 0) {
                        constraint[0] = off.clone();
                    }
                    off.x = cur.x + (((cur.y <= 0 && (cur.y < 0 || cur.x < 0))) ? 1 : -1);
                    off.y = cur.y + (((cur.x >= 0 && (cur.x > 0 || cur.y < 0))) ? 1 : -1);
                    if (xprod(constraint[1], off) <= 0) {
                        constraint[1] = off.clone();
                    }
                }
                
                k1 = k;
                k = nc[k1];
                if (!cyclic(k, i, k1)) {
                    break;
                }
            }
            
            if (foundk) {
                {i--;continue;
                }
            }  // point along k1..k which satisfied the constraint.    // k is the first one violating it. We now need to find the last    // k1 was the last "corner" satisfying the current constraint, and  
            
            
            
            
            
            
            
            dk.x = sign(pt[k].x - pt[k1].x);
            dk.y = sign(pt[k].y - pt[k1].y);
            cur.x = pt[k1].x - pt[i].x;
            cur.y = pt[k1].y - pt[i].y;
            
            // find largest integer j such that xprod(constraint[0], cur+j*dk)
            // >= 0 and xprod(constraint[1], cur+j*dk) <= 0. Use bilinearity
            // of xprod.
            a = xprod(constraint[0], cur);
            b = xprod(constraint[0], dk);
            c = xprod(constraint[1], cur);
            d = xprod(constraint[1], dk);
            
            // find largest integer j such that a+j*b >= 0 and c+j*d <= 0. This
            // can be solved with integer arithmetic.
            j = Int.MAX_VALUE;
            if (b < 0) {
                j = floordiv(a, -b);
            }
            if (d > 0) {
                j = min(j, floordiv(-c, d));
            }
            pivot[i] = mod(k1 + j, n);
            i--;
        }  // for all i' with i <= i' < k, i' < k <= pivk[i']. */    // for each i, let lon[i] be the largest k such that    // Clean up:  
        
        
        
        
        
        
        
        
        j = pivot[n - 1];
        path.lon[n - 1] = j;
        
        i = n - 2;
        while (i >= 0){
            if (cyclic(i + 1, pivot[i], j)) {
                j = pivot[i];
            }
            path.lon[i] = j;
            i--;
        }
        
        i = n - 1;
        while (cyclic(mod(i + 1, n), j, path.lon[i])){
            path.lon[i] = j;
            i--;
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // STAGE 2
    // Calculate the optimal polygon (Sec. 2.2.2 - 2.2.4).
    /////////////////////////////////////////////////////////////////////////
    
    /* 
		 * Auxiliary function: calculate the penalty of an edge from i to j in
		 * the given path. This needs the "lon" and "sum*" data.
		 */
    private function penalty3(path : Path, i : Int, j : Int) : Float
    {
        var n : Int = path.pt.length;
        
        // assume 0 <= i < j <= n
        var sums : Vector<SumStruct> = path.sums;
        var pt : Vector<PointInt> = path.pt;
        
        var r : Int = 0;  // rotations from i to j  
        if (j >= n) {
            j -= n;
            r++;
        }
        
        var x : Float = sums[j + 1].x - sums[i].x + r * sums[n].x;
        var y : Float = sums[j + 1].y - sums[i].y + r * sums[n].y;
        var x2 : Float = sums[j + 1].x2 - sums[i].x2 + r * sums[n].x2;
        var xy : Float = sums[j + 1].xy - sums[i].xy + r * sums[n].xy;
        var y2 : Float = sums[j + 1].y2 - sums[i].y2 + r * sums[n].y2;
        var k : Float = j + 1 - i + r * n;
        
        var px : Float = (pt[i].x + pt[j].x) / 2.0 - pt[0].x;
        var py : Float = (pt[i].y + pt[j].y) / 2.0 - pt[0].y;
        var ey : Float = (pt[j].x - pt[i].x);
        var ex : Float = -(pt[j].y - pt[i].y);
        
        var a : Float = ((x2 - 2 * x * px) / k + px * px);
        var b : Float = ((xy - x * py - y * px) / k + px * py);
        var c : Float = ((y2 - 2 * y * py) / k + py * py);
        
        return Math.sqrt(ex * ex * a + 2 * ex * ey * b + ey * ey * c);
    }
    
    /*
		 * Find the optimal polygon.
		 */
    private function bestpolygon(path : Path) : Void
    {
        var i : Int;
        var j : Int;
        var m : Int;
        var k : Int;
        var n : Int = path.pt.length;
        var pen : Vector<Float> = new Vector<Float>(n + 1);  // penalty vector
        var prev : Vector<Int> = new Vector<Int>(n + 1);  // best path pointer vector
        var clip0 : Vector<Int> = new Vector<Int>(n);  // longest segment pointer, non-cyclic
        var clip1 : Vector<Int> = new Vector<Int>(n + 1);  // backwards segment pointer, non-cyclic
        var seg0 : Vector<Int> = new Vector<Int>(n + 1);  // forward segment bounds, m <= n
        var seg1 : Vector<Int> = new Vector<Int>(n + 1);  // backward segment bounds, m <= n
        
        var thispen : Float;
        var best : Float;
        var c : Int;
        
        // Calculate clipped paths
        for (i in 0...n){
            c = mod(path.lon[mod(i - 1, n)] - 1, n);
            if (c == i) {
                c = mod(i + 1, n);
            }
            clip0[i] = ((c < i)) ? n : c;
        }  // j <= clip0[i] iff clip1[j] <= i, for i,j = 0..n    // calculate backwards path clipping, non-cyclic.  
        
        
        
        
        
        j = 1;
        for (i in 0...n){
            while (j <= clip0[i]){
                clip1[j] = i;
                j++;
            }
        }  // calculate seg0[j] = longest path from 0 with j segments  
        
        
        
        i = 0;
        for (j in 0...n){
            seg0[j] = i;
            i = clip0[i];
        }
        seg0[j] = n;
        
        // calculate seg1[j] = longest path to n with m-j segments
        i = n;
        m = j;
        j = m;
        while (j > 0){
            seg1[j] = i;
            i = clip1[i];
            j--;
        }
        seg1[0] = 0;
        
        // Now find the shortest path with m segments, based on penalty3
        // Note: the outer 2 loops jointly have at most n interations, thus
        // the worst-case behavior here is quadratic. In practice, it is
        // close to linear since the inner loop tends to be short.
        pen[0] = 0;
        for (j in 1...m + 1){
            for (i in seg1[j]...seg0[j] + 1){
                best = -1;
                k = seg0[j - 1];
                while (k >= clip1[i]){
                    thispen = penalty3(path, k, i) + pen[k];
                    if (best < 0 || thispen < best) {
                        prev[i] = k;
                        best = thispen;
                    }
                    k--;
                }
                pen[i] = best;
            }
        }

        // read off shortest path
        path.po = new Vector<Int>(m);

        i = n;
        j = m - 1;
        while (i > 0){
            i = prev[i];
            path.po[j] = i;
            j--;
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // STAGE 3
    // Vertex adjustment (Sec. 2.3.1).
    /////////////////////////////////////////////////////////////////////////
    
    /*
		 * Adjust vertices of optimal polygon: calculate the intersection of
		 * the two "optimal" line segments, then move it into the unit square
		 * if it lies outside.
		 */
    private function adjust_vertices(path : Path) : Void
    {
        var pt : Vector<PointInt> = path.pt;
        var po : Vector<Int> = path.po;
        
        var n : Int = pt.length;
        var m : Int = po.length;
        
        var x0 : Int = pt[0].x;
        var y0 : Int = pt[0].y;
        
        var i : Int;
        var j : Int;
        var k : Int;
        var l : Int;
        
        var d : Float;
        var v : Vector<Float> = new Vector<Float>(3);
        var q : Vector<Vector<Vector<Float>>> = new Vector<Vector<Vector<Float>>>(m);
        
        var ctr : Vector<Point> = new Vector<Point>(m);
        var dir : Vector<Point> = new Vector<Point>(m);
        
        for (i in 0...m){
            q[i] = new Vector<Vector<Float>>(3);
            for (j in 0...3){
                q[i][j] = new Vector<Float>(3);
            }
            ctr[i] = new Point();
            dir[i] = new Point();
        }
        
        var s : Point = new Point();
        
        path.curves = new PrivCurve(m);
        
        // calculate "optimal" point-slope representation for each line segment
        for (i in 0...m){
            j = po[mod(i + 1, m)];
            j = mod(j - po[i], n) + po[i];
            pointslope(path, po[i], j, ctr[i], dir[i]);
        }

        // represent each line segment as a singular quadratic form;
        // the distance of a point (x,y) from the line segment will be
        // (x,y,1)Q(x,y,1)^t, where Q=q[i]
        for (i in 0...m){
            d = dir[i].x * dir[i].x + dir[i].y * dir[i].y;
            if (d == 0) {
                for (j in 0...3){
                    for (k in 0...3){
                        q[i][j][k] = 0;
                    }
                }
            }
            else {
                v[0] = dir[i].y;
                v[1] = -dir[i].x;
                v[2] = -v[1] * ctr[i].y - v[0] * ctr[i].x;
                for (l in 0...3){
                    for (k in 0...3){
                        q[i][l][k] = v[l] * v[k] / d;
                    }
                }
            }
        }

        // now calculate the "intersections" of consecutive segments.
        // Instead of using the actual intersection, we find the point
        // within a given unit square which minimizes the square distance to
        // the two lines.
        for (i in 0...m){
            var Q : Vector<Vector<Float>> = new Vector<Vector<Float>>(3);
            var w : Point = new Point();
            var dx : Float;
            var dy : Float;
            var det : Float;
            var min : Float;  // minimum for minimum of quad. form  
            var cand : Float;  // candidate for minimum of quad. form  
            var xmin : Float;  // coordinate of minimum  
            var ymin : Float;  // coordinate of minimum  
            var z : Int;
            
            for (j in 0...3){
                Q[j] = new Vector<Float>(3);
            }  // let s be the vertex, in coordinates relative to x0/y0
            
            s.x = pt[po[i]].x - x0;
            s.y = pt[po[i]].y - y0;
            
            // intersect segments i-1 and i
            j = mod(i - 1, m);
            
            // add quadratic forms
            for (l in 0...3){
                for (k in 0...3){
                    Q[l][k] = q[j][l][k] + q[i][l][k];
                }
            }
            
            while (true)
            {
                /* minimize the quadratic form Q on the unit square */
                /* find intersection */
                det = Q[0][0] * Q[1][1] - Q[0][1] * Q[1][0];
                if (det != 0) {
                    w.x = (-Q[0][2] * Q[1][1] + Q[1][2] * Q[0][1]) / det;
                    w.y = (Q[0][2] * Q[1][0] - Q[1][2] * Q[0][0]) / det;
                    break;
                }  // orthogonal axis, through the center of the unit square    // matrix is singular - lines are parallel. Add another,  
                
                
                
                
                
                if (Q[0][0] > Q[1][1]) {
                    v[0] = -Q[0][1];
                    v[1] = Q[0][0];
                }
                else if (Q[1][1] != 0) {
                    v[0] = -Q[1][1];
                    v[1] = Q[1][0];
                }
                else {
                    v[0] = 1;
                    v[1] = 0;
                }
                
                d = v[0] * v[0] + v[1] * v[1];
                v[2] = -v[1] * s.y - v[0] * s.x;
                for (l in 0...3){
                    for (k in 0...3){
                        Q[l][k] += v[l] * v[k] / d;
                    }
                }
            }
            
            dx = Math.abs(w.x - s.x);
            dy = Math.abs(w.y - s.y);
            if (dx <= 0.5 && dy <= 0.5) {
                // - 1 because we have a additional border set to the bitmap
                path.curves.vertex[i] = new Point(w.x + x0, w.y + y0);
                {i++;continue;
                }
            }  // now minimize quadratic on boundary of square    // the minimum was not in the unit square;  
            
            
            
            
            
            min = quadform(Q, s);
            xmin = s.x;
            ymin = s.y;
            
            if (Q[0][0] != 0) {
                for (z in 0...2){
                    // value of the y-coordinate
                    w.y = s.y - 0.5 + z;
                    w.x = -(Q[0][1] * w.y + Q[0][2]) / Q[0][0];
                    dx = Math.abs(w.x - s.x);
                    cand = quadform(Q, w);
                    if (dx <= 0.5 && cand < min) {
                        min = cand;
                        xmin = w.x;
                        ymin = w.y;
                    }
                }
            }
            
            if (Q[1][1] != 0) {
                for (z in 0...2){
                    // value of the x-coordinate
                    w.x = s.x - 0.5 + z;
                    w.y = -(Q[1][0] * w.x + Q[1][2]) / Q[1][1];
                    dy = Math.abs(w.y - s.y);
                    cand = quadform(Q, w);
                    if (dy <= 0.5 && cand < min) {
                        min = cand;
                        xmin = w.x;
                        ymin = w.y;
                    }
                }
            }  // check four corners  
            
            
            
            for (l in 0...2){
                for (k in 0...2){
                    w.x = s.x - 0.5 + l;
                    w.y = s.y - 0.5 + k;
                    cand = quadform(Q, w);
                    if (cand < min) {
                        min = cand;
                        xmin = w.x;
                        ymin = w.y;
                    }
                }
            }  // - 1 because we have a additional border set to the bitmap  
            
            
            
            path.curves.vertex[i] = new Point(xmin + x0 - 1, ymin + y0 - 1);
            {i++;continue;
            }
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // STAGE 4
    // Smoothing and corner analysis (Sec. 2.3.3).
    /////////////////////////////////////////////////////////////////////////
    
    private function smooth(curve : PrivCurve, sign : Int, alphaMax : Float) : Void
    {
        var m : Int = curve.n;
        
        var i : Int;
        var j : Int;
        var k : Int;
        var dd : Float;
        var denom : Float;
        var alpha : Float;
        
        var p2 : Point;
        var p3 : Point;
        var p4 : Point;
        
        if (sign < 0) {
            /* reverse orientation of negative paths */
            i = 0;
            j = m - 1;
            while (i < j){
                var tmp : Point = curve.vertex[i];
                curve.vertex[i] = curve.vertex[j];
                curve.vertex[j] = tmp;
                i++;
                j--;
            }
        }  /* examine each vertex and find its best fit */  
        
        
        
        for (i in 0...m){
            j = mod(i + 1, m);
            k = mod(i + 2, m);
            p4 = interval(1 / 2.0, curve.vertex[k], curve.vertex[j]);
            
            denom = ddenom(curve.vertex[i], curve.vertex[k]);
            if (denom != 0) {
                dd = dpara(curve.vertex[i], curve.vertex[j], curve.vertex[k]) / denom;
                dd = Math.abs(dd);
                alpha = ((dd > 1)) ? (1 - 1.0 / dd) : 0;
                alpha = alpha / 0.75;
            }
            else {
                alpha = 4 / 3;
            }  // remember "original" value of alpha */  
            
            
            
            curve.alpha0[j] = alpha;
            
            if (alpha > alphaMax) {
                // pointed corner
                curve.tag[j] = POTRACE_CORNER;
                curve.controlPoints[j][1] = curve.vertex[j];
                curve.controlPoints[j][2] = p4;
            }
            else {
                if (alpha < 0.55) {
                    alpha = 0.55;
                }
                else if (alpha > 1) {
                    alpha = 1;
                }
                p2 = interval(.5 + .5 * alpha, curve.vertex[i], curve.vertex[j]);
                p3 = interval(.5 + .5 * alpha, curve.vertex[k], curve.vertex[j]);
                curve.tag[j] = POTRACE_CURVETO;
                curve.controlPoints[j][0] = p2;
                curve.controlPoints[j][1] = p3;
                curve.controlPoints[j][2] = p4;
            }  // store the "cropped" value of alpha  
            
            curve.alpha[j] = alpha;
            curve.beta[j] = 0.5;
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // STAGE 5
    // Curve optimization (Sec. 2.4).
    /////////////////////////////////////////////////////////////////////////
    
    /*
		 * Optimize the path p, replacing sequences of Bezier segments by a
		 * single segment when possible.
		 */
    private function opticurve(path : Path, optTolerance : Float) : Void
    {
        var m : Int = path.curves.n;
        var pt : Vector<Int> = new Vector<Int>(m);
        var pen : Vector<Float> = new Vector<Float>(m + 1);
        var len : Vector<Int> = new Vector<Int>(m + 1);
        var opt : Vector<Opti> = new Vector<Opti>(m + 1);
        var convc : Vector<Int> = new Vector<Int>(m);
        var areac : Vector<Float> = new Vector<Float>(m + 1);
        
        var i : Int;
        var j : Int;
        var area : Float;
        var alpha : Float;
        var p0 : Point;
        var i1 : Int;
        var o : Opti = new Opti();
        var r : Bool;
        
        // Pre-calculate convexity: +1 = right turn, -1 = left turn, 0 = corner
        for (i in 0...m){
            if (path.curves.tag[i] == POTRACE_CURVETO) {
                convc[i] = sign(dpara(path.curves.vertex[mod(i - 1, m)], path.curves.vertex[i], path.curves.vertex[mod(i + 1, m)]));
            }
            else {
                convc[i] = 0;
            }
        }  // Pre-calculate areas  
        
        
        
        area = 0;
        areac[0] = 0;
        p0 = path.curves.vertex[0];
        for (i in 0...m){
            i1 = mod(i + 1, m);
            if (path.curves.tag[i1] == POTRACE_CURVETO) {
                alpha = path.curves.alpha[i1];
                area += 0.3 * alpha * (4 - alpha) * dpara(path.curves.controlPoints[i][2], path.curves.vertex[i1], path.curves.controlPoints[i1][2]) / 2;
                area += dpara(p0, path.curves.controlPoints[i][2], path.curves.controlPoints[i1][2]) / 2;
            }
            areac[i + 1] = area;
        }
        
        pt[0] = -1;
        pen[0] = 0;
        len[0] = 0;
        
        // Fixme:
        // We always start from a fixed point -- should find the best curve cyclically ###
        
        for (j in 1...m + 1){
            // Calculate best path from 0 to j
            pt[j] = j - 1;
            pen[j] = pen[j - 1];
            len[j] = len[j - 1] + 1;
            
            i = j - 2;
            while (i >= 0){
                r = opti_penalty(path, i, mod(j, m), o, optTolerance, convc, areac);
                if (r) {
                    break;
                }
                if (len[j] > len[i] + 1 || (len[j] == len[i] + 1 && pen[j] > pen[i] + o.pen)) {
                    pt[j] = i;
                    pen[j] = pen[i] + o.pen;
                    len[j] = len[i] + 1;
                    opt[j] = o.clone();
                }
                i--;
            }
        }
        
        var om : Int = len[m];
        
        path.optimizedCurves = new PrivCurve(om);
        
        var s : Vector<Float> = new Vector<Float>(om);
        var t : Vector<Float> = new Vector<Float>(om);
        
        j = m;
        i = om - 1;
        while (i >= 0){
            var jm : Int = mod(j, m);
            if (pt[j] == j - 1) {
                path.optimizedCurves.tag[i] = path.curves.tag[jm];
                path.optimizedCurves.controlPoints[i][0] = path.curves.controlPoints[jm][0];
                path.optimizedCurves.controlPoints[i][1] = path.curves.controlPoints[jm][1];
                path.optimizedCurves.controlPoints[i][2] = path.curves.controlPoints[jm][2];
                path.optimizedCurves.vertex[i] = path.curves.vertex[jm];
                path.optimizedCurves.alpha[i] = path.curves.alpha[jm];
                path.optimizedCurves.alpha0[i] = path.curves.alpha0[jm];
                path.optimizedCurves.beta[i] = path.curves.beta[jm];
                s[i] = t[i] = 1;
            }
            else {
                path.optimizedCurves.tag[i] = POTRACE_CURVETO;
                path.optimizedCurves.controlPoints[i][0] = opt[j].c[0];
                path.optimizedCurves.controlPoints[i][1] = opt[j].c[1];
                path.optimizedCurves.controlPoints[i][2] = path.curves.controlPoints[jm][2];
                path.optimizedCurves.vertex[i] = interval(opt[j].s, path.curves.controlPoints[jm][2], path.curves.vertex[jm]);
                path.optimizedCurves.alpha[i] = opt[j].alpha;
                path.optimizedCurves.alpha0[i] = opt[j].alpha;
                s[i] = opt[j].s;
                t[i] = opt[j].t;
            }
            j = pt[j];
            i--;
        }  /* Calculate beta parameters */  
        
        
        
        for (i in 0...om){
            i1 = mod(i + 1, om);
            path.optimizedCurves.beta[i] = s[i] / (s[i] + t[i1]);
        }
    }
    
    /*
		 * Calculate best fit from i+.5 to j+.5.  Assume i<j (cyclically).
		 * Return 0 and set badness and parameters (alpha, beta), if
		 * possible. Return 1 if impossible.
		 */
    private function opti_penalty(path : Path, i : Int, j : Int, res : Opti, optTolerance : Float, convc : Vector<Int>, areac : Vector<Float>) : Bool
    {
        var m : Int = path.curves.n;
        var k : Int;
        var k1 : Int;
        var k2 : Int;
        var conv : Int;
        var i1 : Int;
        var area : Float;
        var d : Float;
        var d1 : Float;
        var d2 : Float;
        var pt : Point;
        
        if (i == j) {
            // sanity - a full loop can never be an opticurve
            return true;
        }
        
        k = i;
        i1 = mod(i + 1, m);
        k1 = mod(k + 1, m);
        conv = convc[k1];
        if (conv == 0) {
            return true;
        }
        d = ddist(path.curves.vertex[i], path.curves.vertex[i1]);
        k = k1;
        while (k != j){
            k1 = mod(k + 1, m);
            k2 = mod(k + 2, m);
            if (convc[k1] != conv) {
                return true;
            }
            if (sign(cprod(path.curves.vertex[i], path.curves.vertex[i1], path.curves.vertex[k1], path.curves.vertex[k2])) != conv) {
                return true;
            }
            if (iprod1(path.curves.vertex[i], path.curves.vertex[i1], path.curves.vertex[k1], path.curves.vertex[k2]) < d * ddist(path.curves.vertex[k1], path.curves.vertex[k2]) * COS179) {
                return true;
            }
            k = k1;
        }  // the curve we're working in:  
        
        
        
        var p0 : Point = path.curves.controlPoints[mod(i, m)][2];
        var p1 : Point = path.curves.vertex[mod(i + 1, m)];
        var p2 : Point = path.curves.vertex[mod(j, m)];
        var p3 : Point = path.curves.controlPoints[mod(j, m)][2];
        
        // determine its area
        area = areac[j] - areac[i];
        area -= dpara(path.curves.vertex[0], path.curves.controlPoints[i][2], path.curves.controlPoints[j][2]) / 2;
        if (i >= j) {
            area += areac[m];
        }

        // find intersection o of p0p1 and p2p3.
        // Let t,s such that o = interval(t, p0, p1) = interval(s, p3, p2).
        // Let A be the area of the triangle (p0, o, p3).

        var A1 : Float = dpara(p0, p1, p2);
        var A2 : Float = dpara(p0, p1, p3);
        var A3 : Float = dpara(p0, p2, p3);
        var A4 : Float = A1 + A3 - A2;
        
        if (A2 == A1) {
            // this should never happen
            return true;
        }
        
        var t : Float = A3 / (A3 - A4);
        var s : Float = A2 / (A2 - A1);
        var A : Float = A2 * t / 2.0;
        
        if (A == 0) {
            // this should never happen
            return true;
        }
        
        var R : Float = area / A;  // relative area  
        var alpha : Float = 2 - Math.sqrt(4 - R / 0.3);  // overall alpha for p0-o-p3 curve  
        
        res.c = new Vector<Point>(2);
        res.c[0] = interval(t * alpha, p0, p1);
        res.c[1] = interval(s * alpha, p3, p2);
        res.alpha = alpha;
        res.t = t;
        res.s = s;
        
        p1 = res.c[0];
        p2 = res.c[1];  // the proposed curve is now (p0,p1,p2,p3)  
        
        res.pen = 0;
        
        // Calculate penalty
        // Check tangency with edges
        k = mod(i + 1, m);
        while (k != j){
            k1 = mod(k + 1, m);
            t = tangent(p0, p1, p2, p3, path.curves.vertex[k], path.curves.vertex[k1]);
            if (t < -0.5) {
                return true;
            }
            pt = bezier(t, p0, p1, p2, p3);
            d = ddist(path.curves.vertex[k], path.curves.vertex[k1]);
            if (d == 0) {
                // this should never happen
                return true;
            }
            d1 = dpara(path.curves.vertex[k], path.curves.vertex[k1], pt) / d;
            if (Math.abs(d1) > optTolerance) {
                return true;
            }
            if (iprod(path.curves.vertex[k], path.curves.vertex[k1], pt) < 0 || iprod(path.curves.vertex[k1], path.curves.vertex[k], pt) < 0) {
                return true;
            }
            res.pen += d1 * d1;
            k = k1;
        }  // Check corners  
        
        
        
        k = i;
        while (k != j){
            k1 = mod(k + 1, m);
            t = tangent(p0, p1, p2, p3, path.curves.controlPoints[k][2], path.curves.controlPoints[k1][2]);
            if (t < -0.5) {
                return true;
            }
            pt = bezier(t, p0, p1, p2, p3);
            d = ddist(path.curves.controlPoints[k][2], path.curves.controlPoints[k1][2]);
            if (d == 0) {
                // this should never happen
                return true;
            }
            d1 = dpara(path.curves.controlPoints[k][2], path.curves.controlPoints[k1][2], pt) / d;
            d2 = dpara(path.curves.controlPoints[k][2], path.curves.controlPoints[k1][2], path.curves.vertex[k1]) / d;
            d2 *= 0.75 * path.curves.alpha[k1];
            if (d2 < 0) {
                d1 = -d1;
                d2 = -d2;
            }
            if (d1 < d2 - optTolerance) {
                return true;
            }
            if (d1 < d2) {
                res.pen += (d1 - d2) * (d1 - d2);
            }
            k = k1;
        }
        
        return false;
    }
    
    private function pathlist_to_curvearrayslist(plists : Array<Array<Path>>) : Array<Array<Array<Curve>>>
    {
        var res : Array<Array<Array<Curve>>> = Array<Array<Array<Curve>>>();
        
        /* call downstream function with each path */
        for (j in 0...plists.length) {

            var plist : Array<Path> = plists[j];
            var clists : Array<Array<Curve>> = Array<Array<Curve>>();
            res.push(clists);
            
            for (i in 0...plist.length){
                var p : Path = plist[i];
                var A : Point = p.curves.controlPoints[p.curves.n - 1][2];
                var curves : Array<Curve> = new Array<Curve>();
                for (k in 0...p.curves.n){
                    var C : Point = p.curves.controlPoints[k][0];
                    var D : Point = p.curves.controlPoints[k][1];
                    var E : Point = p.curves.controlPoints[k][2];
                    if (p.curves.tag[k] == POTRACE_CORNER) {
                        add_curve(curves, A, A, D, D);
                        add_curve(curves, D, D, E, E);
                    }
                    else {
                        add_curve(curves, A, C, D, E);
                    }
                    A = E;
                }
                if (curves.length > 0) 
                {
                    var cl : Curve = curves[curves.length - 1];
                    var cf : Curve = curves[0];
                    if ((cl.kind == CurveKind.LINE) && (cf.kind == CurveKind.LINE) && iprod(cl.b, cl.a, cf.b) < 0 && (Math.abs(xprodf(
                                        new Point(cf.b.x - cf.a.x, cf.b.y - cf.a.y),
                                        new Point(cl.a.x - cl.a.x, cl.b.y - cl.a.y))) < 0.01)) 
                    {
                        curves[0] = new Curve(CurveKind.LINE, cl.a, cl.a, cl.a, cf.b);
                        curves.pop();
                    }
                    var curveList : Array<Curve> = new Array<Curve>>();
                    for (ci in 0...curves.length){
                        curveList.push(curves[ci]);
                    }
                    clists.push(curveList);
                }
            }
        }
        return res;
    }
    
    private function add_curve(curves : Array<Curve>, a : Point, cpa : Point, cpb : Point, b : Point) : Void
    {
        var kind : Int;
        if ((Math.abs(xprodf(new Point(cpa.x - a.x, cpa.y - a.y), new Point(b.x - a.x, b.y - a.y))) < 0.01) &&
            (Math.abs(xprodf(new Point(cpb.x - b.x, cpb.y - b.y), new Point(b.x - a.x, b.y - a.y))) < 0.01)) {
            kind = CurveKind.LINE;
        }
        else {
            kind = CurveKind.BEZIER;
        }
        if ((kind == CurveKind.LINE)) {
            if ((curves.length > 0) && curves[curves.length - 1]).kind == CurveKind.LINE)) {
                var c : Curve = curves[curves.length - 1];
                if ((Math.abs(xprodf(new Point(c.b.x - c.a.x, c.b.y - c.a.y), new Point(b.x - a.x, b.y - a.y))) < 0.01) && (iprod(c.b, c.a, b) < 0)) {
                    curves[curves.length - 1] = new Curve(kind, c.a, c.a, c.a, b);
                }
                else {
                    curves.push(new Curve(CurveKind.LINE, a, cpa, cpb, b));
                }
            }
            else {
                curves.push(new Curve(CurveKind.LINE, a, cpa, cpb, b));
            }
        }
        else {
            curves.push(new Curve(CurveKind.BEZIER, a, cpa, cpb, b));
        }
    }
    
    /////////////////////////////////////////////////////////////////////////
    // AUXILIARY FUNCTIONS
    /////////////////////////////////////////////////////////////////////////
    
    /*
		 * Return a direction that is 90 degrees counterclockwise from p2-p0,
		 * but then restricted to one of the major wind directions (n, nw, w, etc)
		 */
    private function dorth_infty(p0 : Point, p2 : Point) : PointInt
    {
        return new PointInt(-sign(p2.y - p0.y), sign(p2.x - p0.x));
    }
    
    /*
		 * Return (p1-p0) x (p2-p0), the area of the parallelogram
		 */
    private function dpara(p0 : Point, p1 : Point, p2 : Point) : Float{
        return (p1.x - p0.x) * (p2.y - p0.y) - (p2.x - p0.x) * (p1.y - p0.y);
    }
    
    /*
		 * ddenom/dpara have the property that the square of radius 1 centered
		 * at p1 intersects the line p0p2 iff |dpara(p0,p1,p2)| <= ddenom(p0,p2)
		 */
    private function ddenom(p0 : Point, p2 : Point) : Float
    {
        var r : PointInt = dorth_infty(p0, p2);
        return r.y * (p2.x - p0.x) - r.x * (p2.y - p0.y);
    }
    
    /*
		 * Return true if a <= b < c < a, in a cyclic sense (mod n)
		 */
    private function cyclic(a : Int, b : Int, c : Int) : Bool
    {
        if (a <= c) {
            return (a <= b && b < c);
        }
        else {
            return (a <= b || b < c);
        }
    }
    
    /*
		 * Determine the center and slope of the line i..j. Assume i < j.
		 * Needs "sum" components of p to be set.
		 */
    private function pointslope(path : Path, i : Int, j : Int, ctr : Point, dir : Point) : Void
    {
        // assume i < j
        var n : Int = path.pt.length;
        var sums : Vector<SumStruct> = path.sums;
        var l : Float;
        var r : Int = 0;  // rotations from i to j  
        
        while (j >= n){
            j -= n;
            r++;
        }
        while (i >= n){
            i -= n;
            r--;
        }
        while (j < 0){
            j += n;
            r--;
        }
        while (i < 0){
            i += n;
            r++;
        }
        
        var x : Float = sums[j + 1].x - sums[i].x + r * sums[n].x;
        var y : Float = sums[j + 1].y - sums[i].y + r * sums[n].y;
        var x2 : Float = sums[j + 1].x2 - sums[i].x2 + r * sums[n].x2;
        var xy : Float = sums[j + 1].xy - sums[i].xy + r * sums[n].xy;
        var y2 : Float = sums[j + 1].y2 - sums[i].y2 + r * sums[n].y2;
        var k : Float = j + 1 - i + r * n;
        
        ctr.x = x / k;
        ctr.y = y / k;
        
        var a : Float = (x2 - x * x / k) / k;
        var b : Float = (xy - x * y / k) / k;
        var c : Float = (y2 - y * y / k) / k;
        
        var lambda2 : Float = (a + c + Math.sqrt((a - c) * (a - c) + 4 * b * b)) / 2;  // larger e.value  
        
        // now find e.vector for lambda2
        a -= lambda2;
        c -= lambda2;
        
        if (Math.abs(a) >= Math.abs(c)) {
            l = Math.sqrt(a * a + b * b);
            if (l != 0) {
                dir.x = -b / l;
                dir.y = a / l;
            }
        }
        else {
            l = Math.sqrt(c * c + b * b);
            if (l != 0) {
                dir.x = -c / l;
                dir.y = b / l;
            }
        }
        if (l == 0) {
            // sometimes this can happen when k=4:
            // the two eigenvalues coincide
            dir.x = dir.y = 0;
        }
    }
    
    /*
		 * Apply quadratic form Q to vector w = (w.x, w.y)
		 */
    private function quadform(Q : Vector<Vector<Float>>, w : Point) : Float
    {
        var sum : Float = 0;
        var v : Vector<Float> = new Vector<Float>(3);
        v[0] = w.x;
        v[1] = w.y;
        v[2] = 1;
        for (i in 0...3){
            for (j in 0...3){
                sum += v[i] * Q[i][j] * v[j];
            }
        }
        return sum;
    }
    
    /*
		 * Calculate point of a bezier curve
		 */
    private function bezier(t : Float, p0 : Point, p1 : Point, p2 : Point, p3 : Point) : Point
    {
        var s : Float = 1 - t;
        var res : Point = new Point();
        
        // Note: a good optimizing compiler (such as gcc-3) reduces the
        // following to 16 multiplications, using common subexpression
        // elimination.
        
        // Note [cw]: Flash: fudeu! ;)
        
        res.x = s * s * s * p0.x + 3 * (s * s * t) * p1.x + 3 * (t * t * s) * p2.x + t * t * t * p3.x;
        res.y = s * s * s * p0.y + 3 * (s * s * t) * p1.y + 3 * (t * t * s) * p2.y + t * t * t * p3.y;
        
        return res;
    }
    
    /*
		 * Calculate the point t in [0..1] on the (convex) bezier curve
		 * (p0,p1,p2,p3) which is tangent to q1-q0. Return -1.0 if there is no
		 * solution in [0..1].
		 */
    private function tangent(p0 : Point, p1 : Point, p2 : Point, p3 : Point, q0 : Point, q1 : Point) : Float
    {
        // (1-t)^2 A + 2(1-t)t B + t^2 C = 0
        var A : Float = cprod(p0, p1, q0, q1);
        var B : Float = cprod(p1, p2, q0, q1);
        var C : Float = cprod(p2, p3, q0, q1);
        
        // a t^2 + b t + c = 0
        var a : Float = A - 2 * B + C;
        var b : Float = -2 * A + 2 * B;
        var c : Float = A;
        
        var d : Float = b * b - 4 * a * c;
        
        if (a == 0 || d < 0) {
            return -1;
        }
        
        var s : Float = Math.sqrt(d);
        
        var r1 : Float = (-b + s) / (2 * a);
        var r2 : Float = (-b - s) / (2 * a);
        
        if (r1 >= 0 && r1 <= 1) {
            return r1;
        }
        else if (r2 >= 0 && r2 <= 1) {
            return r2;
        }
        else {
            return -1;
        }
    }
    
    /*
		 * Calculate distance between two points
		 */
    private function ddist(p : Point, q : Point) : Float
    {
        return Math.sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y));
    }
    
    /*
		 * Calculate p1 x p2
		 * (Integer version)
		 */
    private function xprod(p1 : PointInt, p2 : PointInt) : Int
    {
        return p1.x * p2.y - p1.y * p2.x;
    }
    
    /*
		 * Calculate p1 x p2
		 * (Floating point version)
		 */
    private function xprodf(p1 : Point, p2 : Point) : Int
    {
        return p1.x * p2.y - p1.y * p2.x;
    }
    
    /*
		 * Calculate (p1 - p0) x (p3 - p2)
		 */
    private function cprod(p0 : Point, p1 : Point, p2 : Point, p3 : Point) : Float
    {
        return (p1.x - p0.x) * (p3.y - p2.y) - (p3.x - p2.x) * (p1.y - p0.y);
    }
    
    /*
		 * Calculate (p1 - p0) * (p2 - p0)
		 */
    private function iprod(p0 : Point, p1 : Point, p2 : Point) : Float
    {
        return (p1.x - p0.x) * (p2.x - p0.x) + (p1.y - p0.y) * (p2.y - p0.y);
    }
    
    /*
		 * Calculate (p1 - p0) * (p3 - p2)
		 */
    private function iprod1(p0 : Point, p1 : Point, p2 : Point, p3 : Point) : Float
    {
        return (p1.x - p0.x) * (p3.x - p2.x) + (p1.y - p0.y) * (p3.y - p2.y);
    }
    
    private function interval(lambda : Float, a : Point, b : Point) : Point
    {
        return new Point(a.x + lambda * (b.x - a.x), a.y + lambda * (b.y - a.y));
    }
    
    private function abs(a : Int) : Int
    {
        return ((a > 0)) ? a : -a;
    }
    
    private function floordiv(a : Int, n : Int) : Int
    {
        return ((a >= 0)) ? a / n : -1 - (-1 - a) / n;
    }
    
    private function min(a : Int, b : Int) : Int
    {
        return ((a < b)) ? a : b;
    }
    
    private function mod(a : Int, n : Int) : Int
    {
        return ((a >= n)) ? a % n : (((a >= 0)) ? a : n - 1 - (-1 - a) % n);
    }
    
    private function sign(x : Int) : Int
    {
        return ((x > 0)) ? 1 : (((x < 0)) ? -1 : 0);
    }
}

