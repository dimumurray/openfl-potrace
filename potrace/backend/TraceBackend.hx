package potrace.backend;


import potrace.backend.IBackend;

import openfl.geom.Point;

class TraceBackend implements IBackend
{
    public function init(width : Int, height : Int) : Void
    {
        trace("Canvas width:" + width + ", height:" + height);
    }
    
    public function initShape() : Void
    {
        trace("  Shape");
    }
    
    public function initSubShape(positive : Bool) : Void
    {
        trace("    SubShape positive:" + positive);
    }
    
    public function moveTo(a : Point) : Void
    {
        trace("      MoveTo a:" + a);
    }
    
    public function addBezier(a : Point, cpa : Point, cpb : Point, b : Point) : Void
    {
        trace("      Bezier a:" + a + ", cpa:" + cpa + ", cpb:" + cpb + ", b:" + b);
    }
    
    public function addLine(a : Point, b : Point) : Void
    {
        trace("      Line a:" + a + ", b:" + b);
    }
    
    public function exitSubShape() : Void
    {
        
    }
    
    public function exitShape() : Void
    {
        
    }
    
    public function exit() : Void
    {
        
    }

    public function new()
    {
    }
}

