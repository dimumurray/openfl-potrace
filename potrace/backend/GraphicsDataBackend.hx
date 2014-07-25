package potrace.backend;

import potrace.backend.IBackend;

import potrace.geom.CubicCurve;

import openfl.display.GraphicsPath;
import openfl.display.IGraphicsData;
import openfl.geom.Point;
import openfl.Vector;

class GraphicsDataBackend implements IBackend
{
    private var gd : Vector<IGraphicsData>;
    private var gp : GraphicsPath;
    
    public function new(gd : Vector<IGraphicsData>)
    {
        this.gd = gd;
        this.gp = new GraphicsPath();
    }
    
    public function init(width : Int, height : Int) : Void{
    }
    public function initShape() : Void{
    }
    public function initSubShape(positive : Bool) : Void{
    }
    
    public function moveTo(a : Point) : Void
    {
        gp.moveTo(a.x, a.y);
    }
    
    public function addBezier(a : Point, cpa : Point, cpb : Point, b : Point) : Void
    {
        var cubic : CubicCurve = new CubicCurve();
        cubic.drawBezierPts(a, cpa, cpb, b);
        for (i in 0...cubic.result.length){
            var quad : Vector<Point> = cubic.result[i];
            gp.curveTo(quad[1].x, quad[1].y, quad[2].x, quad[2].y);
        }
    }
    
    public function addLine(a : Point, b : Point) : Void
    {
        gp.lineTo(b.x, b.y);
    }
    
    public function exitSubShape() : Void{
    }
    public function exitShape() : Void{
    }
    
    public function exit() : Void
    {
        gd.push(gp);
    }
}

