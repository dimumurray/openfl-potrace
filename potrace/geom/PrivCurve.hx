package potrace.geom;


import openfl.geom.Point;

class PrivCurve
{
    public var n : Int;
    public var tag : Vector<Int>;
    public var controlPoints : Vector<Vector<Point>>;
    public var vertex : Vector<Point>;
    public var alpha : Vector<Float>;
    public var alpha0 : Vector<Float>;
    public var beta : Vector<Float>;
    
    public function new(count : Int)
    {
        // Number of segments
        n = count;
        
        // tag[n] = POTRACE_CORNER or POTRACE_CURVETO
        tag = new Vector<Int>();
        
        // c[n][i]: control points.
        // c[n][0] is unused for tag[n] = POTRACE_CORNER
        controlPoints = new Vector<Vector<Point>>();
        for (i in 0...n){
            controlPoints[i] = new Vector<Point>();
        }  // for POTRACE_CORNER, this equals c[1].  
        
        
        
        vertex = new Vector<Point>();
        
        // only for POTRACE_CURVETO
        alpha = new Vector<Float>();
        
        // for debug output only
        // "uncropped" alpha parameter
        alpha0 = new Vector<Float>();
        
        beta = new Vector<Float>();
    }
}

