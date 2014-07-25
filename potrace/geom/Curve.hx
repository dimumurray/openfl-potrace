package potrace.geom;


import openfl.geom.Point;

class Curve {
    // Bezier or Line
    public var kind : Int;
    
    // Startpoint
    public var a : Point;
    
    // ControlPoint
    public var cpa : Point;
    
    // ControlPoint
    public var cpb : Point;
    
    // Endpoint
    public var b : Point;
    
    public function new(kind : Int, a : Point, cpa : Point, cpb : Point, b : Point) {
        this.kind = kind;
        this.a = a;
        this.cpa = cpa;
        this.cpb = cpb;
        this.b = b;
    }
}

