package potrace.geom;

import openfl.Vector;

import potrace.geom.PointInt;
import potrace.geom.PrivCurve;
import potrace.geom.SumStruct;

class Path
{
    public var area : Int;
    public var monotonIntervals : Vector<MonotonInterval>;
    public var pt : Vector<PointInt>;
    public var lon : Vector<Int>;
    public var sums : Vector<SumStruct>;
    public var po : Vector<Int>;
    public var curves : PrivCurve;
    public var optimizedCurves : PrivCurve;
    public var fCurves : PrivCurve;

    public function new()
    {
    }
}

