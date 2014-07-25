package potrace.geom;

import openfl.geom.Point;
import openfl.Vector;

/**
 * Class for drawing cubic bezier curves.
 * Adapted from bezier_draw_cubic.as and drawing_api_core_extensions.as by Alex Uhlmann.
 * Approved by Robert Penner.
 * @author Robert Penner, Alex Uhlmann
 * @version 0.4 ALPHA
 * -note that line 92 this.mc.moveTo (p1.x, p1.y); is commented out.
 * -ported to AS3
 *
 * Adapted for use with as3potrace by Claus Wahlers
*/
class CubicCurve {
    public var result(get, never) : Vector<Vector<Point>>;
    private var xPen : Float;
    private var yPen : Float;
    private var _result : Vector<Vector<Point>>;

    public function new(){}

    private function intersect2Lines(p1 : Point, p2 : Point, p3 : Point, p4 : Point) : Point {
        var x1 : Float = p1.x;
        var y1 : Float = p1.y;
        var x4 : Float = p4.x;
        var y4 : Float = p4.y;
        var dx1 : Float = p2.x - x1;
        var dx2 : Float = p3.x - x4;

        if (dx1 == 0 && dx2 == 0) {
            return null;
        }

        var m1 : Float = (p2.y - y1) / dx1;
        var m2 : Float = (p3.y - y4) / dx2;

        if (dx1 == 0) {
            // infinity
            return new Point(x1, m2 * (x1 - x4) + y4);
        } else if (dx2 == 0) {  // infinity
            return new Point(x4, m1 * (x4 - x1) + y1);
        }

        var xInt : Float = (-m2 * x4 + y4 + m1 * x1 - y1) / (m1 - m2);
        var yInt : Float = m1 * (xInt - x1) + y1;
        return new Point(xInt, yInt);
    }

    private function midLine(a : Point, b : Point) : Point {
        return new Point((a.x + b.x) / 2, (a.y + b.y) / 2);
    }

    private function bezierSplit(p0 : Point, p1 : Point, p2 : Point, p3 : Point) : Vector<Point> {
        var m : Function = this.midLine;
        var p01 : Point = m(p0, p1);
        var p12 : Point = m(p1, p2);
        var p23 : Point = m(p2, p3);
        var p02 : Point = m(p01, p12);
        var p13 : Point = m(p12, p23);
        var p03 : Point = m(p02, p13);
        var ret : Vector<Point> = new Vector<Point>();

        ret[0] = p0.clone();
        ret[1] = p01;ret[2] = p02;
        ret[3] = p03;ret[4] = p03;
        ret[5] = p13;ret[6] = p23;
        ret[7] = p3.clone();

        return ret;
    }

    private function cBez(a : Point, b : Point, c : Point, d : Point, k : Float) : Void {
        // find intersection between bezier arms
        var s : Point = intersect2Lines(a, b, c, d);

        if (s == null) {
            return;
        }

        // find distance between the midpoints
        var dx : Float = (a.x + d.x + s.x * 4 - (b.x + c.x) * 3) * .125;
        var dy : Float = (a.y + d.y + s.y * 4 - (b.y + c.y) * 3) * .125;

        // split curve if the quadratic isn't close enough
        if (dx * dx + dy * dy > k) {
            // split the curve
            var halves : Vector<Point> = bezierSplit(a, b, c, d);

            // recursive call to subdivide curve
            cBez(a, halves[1], halves[2], halves[3], k);
            cBez(halves[4], halves[5], halves[6], d, k);
        } else {
            // end recursion by drawing quadratic bezier
            var bezier : Vector<Point> = new Vector<Point>();
            bezier[0] = new Point(xPen, yPen);
            bezier[1] = s.clone();
            bezier[2] = d.clone();
            result.push(bezier);
            xPen = d.x;
            yPen = d.y;
        }
    }

    public function drawBezierPts(p1 : Point, p2 : Point, p3 : Point, p4 : Point, tolerance : Float = -1) : Void {
        if (tolerance <= 0) {
            tolerance = 5;
        }

        xPen = p1.x;
        yPen = p1.y;
        _result = new Vector<Vector<Point>>();
        cBez(p1, p2, p3, p4, tolerance * tolerance);
    }

    public function drawBezier(x1 : Float, y1 : Float, x2 : Float, y2 : Float, x3 : Float, y3 : Float, x4 : Float, y4 : Float, tolerance : Float = -1) : Void {
        drawBezierPts(
            new Point(x1, y1),
            new Point(x2, y2),
            new Point(x3, y3),
            new Point(x4, y4),
            tolerance
        );
    }

    public function curveToCubicPts(p1 : Point, p2 : Point, p3 : Point, tolerance : Float = -1) : Void {
        if (tolerance <= 0) {
            tolerance = 5;
        }
        _result = new Vector<Vector<Point>>();
        cBez(new Point(xPen, yPen), p1, p2, p3, tolerance * tolerance);
    }

    public function curveToCubic(x1 : Float, y1 : Float, x2 : Float, y2 : Float, x3 : Float, y3 : Float, tolerance : Float = -1) : Void {
        curveToCubicPts(
            new Point(x1, y1),
            new Point(x2, y2),
            new Point(x3, y3),
            tolerance
        );
    }

    private function get_Result() : Vector<Vector<Point>> {
        return _result;
    }
}