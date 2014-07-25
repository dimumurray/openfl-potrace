package potrace.geom;

import openfl.Vector;

import potrace.geom.PointInt;

class MonotonInterval
{
    public var increasing : Bool;
    public var from : Int;
    public var to : Int;
    
    public var currentId : Int;
    
    public function new(increasing : Bool, from : Int, to : Int)
    {
        this.increasing = increasing;
        this.from = from;
        this.to = to;
    }
    
    public function resetCurrentId(modulo : Int) : Void
    {
        if (!increasing) {
            currentId = mod(min() + 1, modulo);
        }
        else {
            currentId = min();
        }
    }
    
    public function min() : Int
    {
        return (increasing) ? from : to;
    }
    
    public function max() : Int
    {
        return (increasing) ? to : from;
    }
    
    public function minY(pts : Vector<PointInt>) : Int
    {
        return pts[min()].y;
    }
    
    public function maxY(pts : Vector<PointInt>) : Int
    {
        return pts[max()].y;
    }
    
    private function mod(a : Int, n : Int) : Int
    {
        return ((a >= n)) ? a % n : (((a >= 0)) ? a : n - 1 - (-1 - a) % n);
    }
}

