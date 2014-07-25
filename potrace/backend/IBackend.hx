package potrace.backend;


import openfl.geom.Point;

interface IBackend
{

    function init(width : Int, height : Int) : Void;
    function initShape() : Void;
    function initSubShape(positive : Bool) : Void;
    function moveTo(a : Point) : Void;
    function addBezier(a : Point, cpa : Point, cpb : Point, b : Point) : Void;
    function addLine(a : Point, b : Point) : Void;
    function exitSubShape() : Void;
    function exitShape() : Void;
    function exit() : Void;
}

