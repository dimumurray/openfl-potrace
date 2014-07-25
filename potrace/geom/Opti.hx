package potrace.geom;

import openfl.Vector;
import openfl.geom.Point;

class Opti
{
    public var pen : Float;
    public var c : Vector<Point>;
    public var t : Float;
    public var s : Float;
    public var alpha : Float;
    
    public function clone() : Opti
    {
        var o : Opti = new Opti();
        o.pen = pen;
        o.c = new Vector<Point>();
        o.c[0] = c[0].clone();
        o.c[1] = c[1].clone();
        o.t = t;
        o.s = s;
        o.alpha = alpha;
        return o;
    }

    public function new()
    {
    }
}

