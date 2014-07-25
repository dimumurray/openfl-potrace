package potrace;


class POTraceParams
{
    // For a detailed description of all parameters, see:
    // http://potrace.sourceforge.net/potracelib.pdf
    
    // Note that differing from the original, the
    // curveOptimizing parameter is set to false here.
    
    public function new(threshold : Int = 0x888888, thresholdOperator : String = "<=", turdSize : Int = 2, alphaMax : Float = 1, curveOptimizing : Bool = false, optTolerance : Float = 0.2)
    {
        this.threshold = threshold;
        this.thresholdOperator = thresholdOperator;
        this.turdSize = turdSize;
        this.alphaMax = alphaMax;
        this.curveOptimizing = curveOptimizing;
        this.optTolerance = optTolerance;
    }
    
    // Color value for threshold filter applied to bitmap before processing.
    // Defaults to 0x888888
    public var threshold : Int;
    
    // The operator to use when the threshold is applied (ex. "<=", ">", etc).
    // Defaults to "<="
    public var thresholdOperator : String;
    
    // Area of largest path to be ignored (in pixels)
    // Defaults to 2
    public var turdSize : Int;
    
    // Corner threshold, controls the smoothness of the curve.
    // The useful range of this parameter is from 0 (polygon) to 1.3333 (no corners).
    // Defaults to 1
    public var alphaMax : Float;
    
    // Whether to optimize curves or not.
    // Replace sequences of Bezier segments by a single segment when possible.
    // Defaults to false
    public var curveOptimizing : Bool;
    
    // Curve optimizing tolerance
    // Larger values tend to decrease the number of segments, at the expense of less accuracy.
    // The useful range is from 0 to infinty, although in practice one would hardly choose values greater than 1 or so.
    // Defaults to 0.2
    public var optTolerance : Float;
}

